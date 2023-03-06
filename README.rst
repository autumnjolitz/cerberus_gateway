===================
Cerberus Gateway
===================


Status
==========

- provision a DragonFly VBOX image as a "builder-builder" ✅ 
    + Create a HAMMER2 reference installation ✅
    + Build kernel/userland sources for faster iteration in cerberus-image ✅ 
- create the builder of images (using nrelease as a skeleton for USB image formation)
    + investigate if nrelease is a good idea or deriving out a new approach is required
- install gateway related files
- create Vagrant box
- test networking


Purpose
=========

A project that uses Vagrant and DragonFly to build a LiveUSB image with a custom root skel, custom packages suitable for testing in a VirtualBox network and ultimate use on a thin 2-ethernet port box to serve as a gateway.

The final goal is to generate a ``.img`` file suitable for ``dd if=cerberus.img of=...`` onto a microSD card.

Target hardware is an `OnLogic Apollo Lake N4200 Pico-ITX (EPM163) <https://www.onlogic.com/epm163/>`_.

What will this accomplish:

- low power consumption x84_64 DragonFly gateway

Test
=======


Topology::

    +------------+     +-------------+        +---------------+
    | Internet   |-----| Cerberus GW |--------| Test Client 1 |
    | (vbox)     |     |             |        |               |
    +------------+     +-------------+        +---------------+
                                   |         /
                               +----------------+
                               |  Test Client 2 |
                               |                |
                               +----------------+

Cerberus will:
    - Provide a DHCP network of 192.168.1.0/24 at ip 192.168.1.1
    - Have a PF to facilitate outside access
    - Provide a VPN

Test Clients will:

    - Connect to the GW via DHCP and configure their networks


Requirements
================

::

    brew install packer


Building
==========

::

    curl 'http://mirror-master.dragonflybsd.org/iso-images/dfly-x86_64-6.4.0_REL.iso.bz2' | bunzip2 -c > dfly-x86_64-6.4.0_REL.iso
    packer init cerberus-builder.pkr.hcl
    packer build cerberus-builder.pkr.hcl
    packer build cerberus-image.pkr.hcl

