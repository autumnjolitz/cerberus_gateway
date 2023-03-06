packer {
  required_plugins {
    virtualbox = {
      version = ">= 0.0.1"
      source  = "github.com/hashicorp/virtualbox"
    }
    sshkey = {
      version = ">= 0.1.0"
      source = "github.com/ivoronin/sshkey"
    }

  }
}

data "sshkey" "install" {
}

source "virtualbox-iso" "dragonfly_base" {
  guest_os_type = "FreeBSD_64"
  cpus = 4
  memory= 4096
  rtc_time_base = "UTC"
  firmware = "efi"

  virtualbox_version_file = ""
  guest_additions_mode = "disable"

  gfx_vram_size = 16
  gfx_controller = "vmsvga"

  iso_url       = "http://mirror-master.dragonflybsd.org/iso-images/dfly-x86_64-6.4.0_REL.iso.bz2?archive=bz2&checksum=md5:5dbf894d9120664a675030c475f25040&filename=dfly-x86_64-6.4.0_REL.iso.bz2"
  iso_checksum  = "md5:ff4d500c7c75b1f88ca4237a6aa861d1"

  boot_wait     = "2s"

  chipset = "ich9"
  iso_interface = "sata"
  hard_drive_interface = "sata"

  sata_port_count = 4
  disk_size = 68000

  hard_drive_nonrotational = true
  hard_drive_discard = true

  ssh_private_key_file      = data.sshkey.install.private_key_path
  ssh_clear_authorized_keys = true
  http_content = {
    "/ssh.pub" = data.sshkey.install.public_key
    "/init.sh" = file("bootstrap/install-with-hammer2-to-disk.sh")
  }

  boot_command  = [
    # "<esc><wait150ms>",
    # "fs1:", # Switch to the Optical CD drive and boot
    # "<enter>",
    # "\\efi\\boot\\bootx64.efi", # Initiate the EFI boot loader
    # "<enter>",
    "<wait1s>",
    "<return><wait70s>",
    "root<return>",
    "sh <return>",  # Switch to bourne shell (not csh)
    "export HTTP_SERVER='http://{{ .HTTPIP }}:{{ .HTTPPort }}' <return>",
    "dhclient em0 && sleep 3 && \\<return>", # Get the ip from the dhcp server
    "fetch $HTTP_SERVER/init.sh && \\<return>",
    "chmod +x init.sh && \\<return>",
    "./init.sh && shutdown -p +0 <return>",
  ]
  vboxmanage = [
    [ "setextradata", "{{.Name}}", "GUI/ScaleFactor", "1.7" ],
    [ "modifyvm", "{{.Name}}", "--firmware", "EFI" ],
    [ "modifyvm", "{{.Name}}", "--nat-localhostreachable1", "on" ],
    [ "storagectl",  "{{.Name}}", "--name", "SATA Controller", "--hostiocache", "on"]
  ]

  shutdown_command = ""
  disable_shutdown = true
  shutdown_timeout = "10m"
}

build {
  name = "cerberus-builder"
  source "virtualbox-iso.dragonfly_base" {
    communicator = "none"
    output_filename  = "cerberus-builder"
    output_directory = "cerberus-builder"
  }
}
