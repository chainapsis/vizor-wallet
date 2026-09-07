"""Virtual Ledger-shaped GATT peer, not a Ledger signer or firmware emulator.

Run with: uv run --with bumble==0.0.234 --with grpcio --with protobuf python peripheral.py
Requires an Android emulator running with -packet-streamer-endpoint default.
"""
import asyncio
from bumble.core import AdvertisingData, UUID
from bumble.device import Device, DeviceConfiguration
from bumble.hci import Address
from bumble.gatt import Characteristic, CharacteristicValue, Service
from bumble.transport import open_transport

SERVICE = '13d63400-2c97-0004-0000-4c6564676572'
NOTIFY = '13d63400-2c97-0004-0001-4c6564676572'
WRITE = '13d63400-2c97-0004-0002-4c6564676572'


async def main():
    async with await open_transport('android-netsim') as transport:
        config = DeviceConfiguration()
        config.address = Address('F0:F1:F2:F3:F4:F7')
        config.name = 'Vizor BLE probe'
        device = Device.from_config_with_hci(config, transport.source, transport.sink)
        notify = Characteristic(NOTIFY, Characteristic.Properties.NOTIFY, 'READABLE', b'')
        jobs = set()

        async def respond(connection, value):
            # Probe commands, intentionally not Ledger APDU framing.
            # 01: normal, 02: delayed, 03: never reply.
            if value == b'\x03':
                print('INJECT no response', flush=True)
                return
            if value == b'\x02':
                await asyncio.sleep(1.5)
            if device.connections.get(connection.handle) is connection:
                await device.notify_subscriber(connection, notify, value + b'\x90\x00')
                print(f'NOTIFY {value.hex()}9000', flush=True)
            else:
                print('DROP response for disconnected session', flush=True)

        def write(connection, value):
            print(f'WRITE {value.hex()}', flush=True)
            job = asyncio.create_task(respond(connection, value))
            jobs.add(job)
            job.add_done_callback(jobs.discard)

        characteristic = Characteristic(WRITE, Characteristic.Properties.WRITE, 'WRITEABLE', CharacteristicValue(write=write))
        device.add_service(Service(SERVICE, [notify, characteristic]))
        device.advertising_data = bytes(AdvertisingData([
            (AdvertisingData.COMPLETE_LOCAL_NAME, b'BLEProbeV2'),
            (AdvertisingData.COMPLETE_LIST_OF_128_BIT_SERVICE_CLASS_UUIDS, bytes(UUID(SERVICE))),
        ]))
        await device.power_on()
        await device.start_advertising(auto_restart=True)
        print('READY virtual Ledger-shaped GATT peripheral', flush=True)
        await asyncio.Event().wait()


if __name__ == '__main__':
    asyncio.run(main())
