import pathlib
import plistlib
import struct
import sys
import zipfile

# ios/Scripts/verify-ipa.py
def verify(path):
    """Validate actual iPhoneOS arm64 binary and bundled resources before delivery."""
    with zipfile.ZipFile(path) as archive:
        assert archive.testzip() is None, 'Corrupt IPA archive'
        prefix = 'Payload/Folia.app/'
        info = plistlib.loads(archive.read(prefix + 'Info.plist'))
        assert float(info['MinimumOSVersion']) >= 26, 'Wrong deployment target'
        assert info['CFBundleSupportedPlatforms'] == ['iPhoneOS'], 'Simulator app cannot be delivered as IPA'
        binary = archive.read(prefix + info['CFBundleExecutable'])
        assert struct.unpack_from('<I', binary)[0] == 0xFEEDFACF, 'Expected thin Mach-O 64-bit executable'
        assert struct.unpack_from('<I', binary, 4)[0] == 0x0100000C, 'Expected arm64 executable'
        archive.getinfo(prefix + 'Lyrics/index.html')
        assert any(name.startswith(prefix + 'Lyrics/assets/') and name.endswith('.js') for name in archive.namelist()), 'Missing lyrics renderer'
        print(f'Validated {pathlib.Path(path).name}: iPhoneOS arm64, iOS {info["MinimumOSVersion"]}, bundled lyrics')

if __name__ == '__main__':
    verify(sys.argv[1])
