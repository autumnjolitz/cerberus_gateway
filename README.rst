===================
Cerberus Gateway
===================


Status
==========

- provision a DragonFly VBOX image ✅ 
- install gateway related files
- create Vagrant box
- test networking


Purpose
=========

A project that uses Vagrant and DragonFly to build a LiveUSB image with a custom root skel, custom packages suitable for testing in a VirtualBox network and ultimate use on a thin 2-ethernet port box to serve as a gateway.

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

    packer init cerberus-dragonfly.pkr.hcl
    packer build cerberus-dragonfly.pkr.hcl

