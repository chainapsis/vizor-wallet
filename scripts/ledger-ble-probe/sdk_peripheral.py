"""Minimal Ledger BLE framing peer for the unmodified Android DMK probe.

Synthetic APDU replies only; no wallet, keys, signatures or Speculos.
Run with uv run --with bumble==0.0.234 --with grpcio --with protobuf python FILE.
Stops after 180 seconds. Log RX/NOTIFY for evidence of actual SDK wire traffic.
"""
import asyncio
from bumble.core import AdvertisingData, UUID
from bumble.device import Device, DeviceConfiguration
from bumble.hci import Address
from bumble.gatt import Characteristic, CharacteristicValue, Service
from bumble.transport import open_transport

BASE = '13d63400-2c97-0004-000{}-4c6564676572'


async def main():
    async with await open_transport('android-netsim') as transport:
        config = DeviceConfiguration()
        config.address = Address('F0:F1:F2:F3:F4:F8')
        config.name = 'DMKProbe'
        device = Device.from_config_with_hci(config, transport.source, transport.sink)
        notify = Characteristic(BASE.format(1), Characteristic.Properties.NOTIFY, 'READABLE', b'')
        jobs = set()

        async def reply(connection, payload, delay=0):
            await asyncio.sleep(delay)
            if device.connections.get(connection.handle) is not connection:
                print('DROP old physical connection', flush=True)
                return
            await device.notify_subscriber(connection, notify, payload)
            print('NOTIFY ' + payload.hex(), flush=True)

        def write(connection, value):
            print('RX ' + value.hex(), flush=True)
            if value == bytes.fromhex('0800000000'):
                payload = value + (connection.att_mtu - 3).to_bytes(2, 'big')
                delay = 0
            else:
                if len(value) < 10 or value[:3] != bytes.fromhex('050000'):
                    raise ValueError('Probe supports only complete single-frame APDUs')
                apdu = value[5:]
                if len(apdu) != int.from_bytes(value[3:5], 'big'):
                    raise ValueError('APDU length mismatch')
                ins = apdu[1]
                delay = {0xf2: 1.5, 0xf3: 2.5}.get(ins, 0)
                if apdu[:2] == bytes.fromhex('b001'):
                    body = bytes.fromhex('01055a6361736805332e392e33009000')
                elif ins in (0xf1, 0xf2, 0xf3):
                    body = bytes([ins - 0xf0, 0x90, 0])
                else:
                    body = bytes.fromhex('6d00')
                payload = bytes.fromhex('050000') + len(body).to_bytes(2, 'big') + body
            job = asyncio.create_task(reply(connection, payload, delay))
            jobs.add(job)
            job.add_done_callback(jobs.discard)

        device.add_service(Service(BASE.format(0), [
            notify,
            Characteristic(BASE.format(2), Characteristic.Properties.WRITE, 'WRITEABLE', CharacteristicValue(write=write)),
            Characteristic(BASE.format(3), Characteristic.Properties.WRITE_WITHOUT_RESPONSE, 'WRITEABLE', CharacteristicValue(write=write)),
        ]))
        device.advertising_data = bytes(AdvertisingData([
            (AdvertisingData.COMPLETE_LOCAL_NAME, b'DMKProbe'),
            (AdvertisingData.COMPLETE_LIST_OF_128_BIT_SERVICE_CLASS_UUIDS, bytes(UUID(BASE.format(0)))),
        ]))
        await device.power_on()
        await device.start_advertising(auto_restart=True)
        print('READY DMKProbe for 180 seconds', flush=True)
        await asyncio.sleep(180)
        for job in jobs:
            job.cancel()
        await asyncio.gather(*jobs, return_exceptions=True)


if __name__ == '__main__':
    asyncio.run(main())
