#!/usr/bin/env python3
"""Fetch pinned, checksum-verified upstream release sources."""
import hashlib
from pathlib import Path
import sys
import urllib.request

SOURCES = [
    ('libmtp-1.1.23.tar.gz',
     'https://downloads.sourceforge.net/project/libmtp/libmtp/1.1.23/libmtp-1.1.23.tar.gz',
     '74a2b6e8cb4a0304e95b995496ea3ac644c29371649b892b856e22f12a0bdeed'),
    ('libusb-1.0.30.tar.bz2',
     'https://github.com/libusb/libusb/releases/download/v1.0.30/libusb-1.0.30.tar.bz2',
     'fea36f34f9156400209595e300840767ab1a385ede1dc7ee893015aea9c6dbaf'),
]


def download(destination):
    root = Path(destination)
    root.mkdir(parents=True, exist_ok=True)
    for name, url, expected in SOURCES:
        path = root / name
        if not path.exists():
            request = urllib.request.Request(url, headers={'User-Agent': 'mac-switch-mtp'})
            with urllib.request.urlopen(request, timeout=60) as response:
                data = response.read()
            if hashlib.sha256(data).hexdigest() != expected:
                raise SystemExit(f'{name}: downloaded source checksum mismatch')
            path.write_bytes(data)
        actual = hashlib.sha256(path.read_bytes()).hexdigest()
        if actual != expected:
            raise SystemExit(f'{name}: cached source checksum mismatch')
        print(f'{actual}  {name}')


if __name__ == '__main__':
    download(sys.argv[1])
