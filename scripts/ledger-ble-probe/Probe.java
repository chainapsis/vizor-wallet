package app.vizor.bleprobe;

import android.app.Activity;
import android.os.*;
import android.bluetooth.*;
import android.bluetooth.le.*;
import android.util.Log;
import java.util.*;

/** Android Bluetooth stack probe; deliberately bypasses Vizor and the Ledger SDK. */
public class Probe extends Activity {
  static final UUID SERVICE = UUID.fromString("13d63400-2c97-0004-0000-4c6564676572");
  static final UUID NOTIFY = UUID.fromString("13d63400-2c97-0004-0001-4c6564676572");
  static final UUID WRITE = UUID.fromString("13d63400-2c97-0004-0002-4c6564676572");
  static final UUID CCCD = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb");
  final Handler handler = new Handler(Looper.getMainLooper());
  BluetoothLeScanner scanner;
  BluetoothDevice peer;
  BluetoothGatt active;
  int stage = 0;
  long sentAt;
  boolean finished;
  void log(String text) { Log.i("VizorBleProbe", text); }
  void fail(String text) { if (!finished) { finished = true; log("FAIL " + text); } }

  @Override public void onCreate(Bundle state) {
    super.onCreate(state);
    scanner = getSystemService(BluetoothManager.class).getAdapter().getBluetoothLeScanner();
    if (scanner == null) { fail("Bluetooth is off"); return; }
    scanner.startScan(Arrays.asList(new ScanFilter.Builder().setDeviceName("BLEProbeV2").setServiceUuid(new ParcelUuid(SERVICE)).build()),
        new ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build(), scan);
    handler.postDelayed(() -> fail("45-second deadline exceeded at stage " + stage), 45000);
  }

  final ScanCallback scan = new ScanCallback() {
    @Override public void onScanResult(int type, ScanResult result) {
      if (peer != null) return;
      peer = result.getDevice();
      scanner.stopScan(this);
      log("PASS discovery " + result.getScanRecord().getDeviceName());
      connect();
    }
    @Override public void onScanFailed(int error) { fail("scan " + error); }
  };

  void connect() { active = peer.connectGatt(this, false, callback, BluetoothDevice.TRANSPORT_LE, BluetoothDevice.PHY_LE_1M_MASK, handler); }
  void write(BluetoothGatt gatt, int value) {
    BluetoothGattCharacteristic characteristic = gatt.getService(SERVICE).getCharacteristic(WRITE);
    characteristic.setValue(new byte[] {(byte) value});
    sentAt = SystemClock.elapsedRealtime();
    if (!gatt.writeCharacteristic(characteristic)) fail("write not started");
  }

  final BluetoothGattCallback callback = new BluetoothGattCallback() {
    @Override public void onConnectionStateChange(BluetoothGatt gatt, int status, int state) {
      if (state == BluetoothProfile.STATE_CONNECTED) {
        log("CONNECTED stage=" + stage);
        if (!gatt.discoverServices()) fail("service discovery not started");
      } else if (state == BluetoothProfile.STATE_DISCONNECTED) {
        gatt.close();
        if ((stage == 2 || stage == 4) && !finished) {
          log("PASS disconnect while response pending");
          stage++;
          handler.post(() -> connect());
        } else if (!finished) fail("unexpected disconnect status=" + status);
      }
    }
    @Override public void onServicesDiscovered(BluetoothGatt gatt, int status) {
      if (status != 0 || gatt.getService(SERVICE) == null) { fail("missing service " + status); return; }
      BluetoothGattCharacteristic notify = gatt.getService(SERVICE).getCharacteristic(NOTIFY);
      gatt.setCharacteristicNotification(notify, true);
      BluetoothGattDescriptor descriptor = notify.getDescriptor(CCCD);
      descriptor.setValue(BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE);
      if (!gatt.writeDescriptor(descriptor)) fail("subscribe not started");
    }
    @Override public void onDescriptorWrite(BluetoothGatt gatt, BluetoothGattDescriptor descriptor, int status) {
      if (status != 0) { fail("subscribe " + status); return; }
      write(gatt, 1);
    }
    @Override public void onCharacteristicWrite(BluetoothGatt gatt, BluetoothGattCharacteristic characteristic, int status) {
      if (status != 0) { fail("write status=" + status); return; }
      if (stage == 2 || stage == 4) handler.postDelayed(() -> gatt.disconnect(), 500);
    }
    @Override public void onCharacteristicChanged(BluetoothGatt gatt, BluetoothGattCharacteristic characteristic) {
      if (finished) return;
      byte[] value = characteristic.getValue();
      if (gatt != active) { fail("notification from stale connection"); return; }
      int expected = stage == 1 ? 2 : 1;
      if (!Arrays.equals(value, new byte[] {(byte) expected, (byte) 0x90, 0})) { fail("unexpected notification stage=" + stage); return; }
      if (stage == 0) {
        log("PASS GATT write and notification"); stage = 1; handler.post(() -> write(gatt, 2));
      } else if (stage == 1) {
        long elapsed = SystemClock.elapsedRealtime() - sentAt;
        if (elapsed < 1400) { fail("delay not exercised"); return; }
        log("PASS delayed notification elapsed=" + elapsed); stage = 2; handler.post(() -> write(gatt, 3));
      } else if (stage == 3) {
        log("PASS reconnect and fresh GATT exchange"); stage = 4; handler.post(() -> write(gatt, 2));
      } else if (stage == 5) {
        stage = 6;
        handler.postDelayed(() -> {
          if (finished) return;
          log("PASS delayed response from disconnected session did not reach new session");
          finished = true; gatt.disconnect();
          log("PASS ALL Android stack scenarios; NOT Vizor/DMK/Speculos E2E");
        }, 2200);
      } else {
        fail("unsolicited notification at stage=" + stage);
      }
    }
  };
}
