packer {
  required_plugins {
    virtualbox = {
      version = ">= 0.0.1"
      source  = "github.com/hashicorp/virtualbox"
    }
    sshkey = {
      version = ">= 1.0.8"
      source = "github.com/ivoronin/sshkey"
    }

  }
}

variable "disk_size_gb" {
    default = 60
    type = number
}

data "sshkey" "install" {
  type = "ed25519"
}

source "virtualbox-iso" "dragonfly_base" {
  headless = true
  guest_os_type = "FreeBSD_64"
  cpus = 4
  memory= 4096
  rtc_time_base = "UTC"
  firmware = "efi"

  virtualbox_version_file = ""
  guest_additions_mode = "disable"

  gfx_vram_size = 16
  gfx_controller = "vmsvga"

  iso_url       = "dfly-x86_64-6.4.0_REL.iso"
  iso_checksum  = "md5:ff4d500c7c75b1f88ca4237a6aa861d1"

  boot_wait     = "2s"

  chipset = "ich9"
  iso_interface = "sata"
  hard_drive_interface = "sata"

  sata_port_count = 4
  disk_size = var.disk_size_gb * 1024

  hard_drive_nonrotational = true
  hard_drive_discard = true
  nested_virt = true
  usb = true

  ssh_private_key_file      = data.sshkey.install.private_key_path
  ssh_clear_authorized_keys = true
  http_content = {
    "/root.pub" = data.sshkey.install.public_key
    "/setup-user.sh" = file("bootstrap/setup-user.sh")
  }

  boot_command  = [
    # "<esc><wait150ms>",
    # "fs1:", # Switch to the Optical CD drive and boot
    # "<enter>",
    # "\\efi\\boot\\bootx64.efi", # Initiate the EFI boot loader
    # "<enter>",
    "<wait1s>",
    "<return><wait80s>",
    "root<return>",
    "dhclient em0 && sleep 3 && \\<return>", # Get the ip from the dhcp server
    "curl 'http://{{ .HTTPIP }}:{{ .HTTPPort }}/setup-user.sh' | sh -s {{ .HTTPIP }} {{ .HTTPPort }} root && \\<return>",
    # "tail -f /var/log/auth.log<return>",
    "exit <return>",
  ]
  vboxmanage = [
    # [ "setextradata", "{{.Name}}", "GUI/ScaleFactor", "1.7" ],
    [ "modifyvm", "{{.Name}}", "--firmware", "EFI" ],
    [ "modifyvm", "{{.Name}}", "--nat-localhostreachable1", "on" ],
    [ "storagectl",  "{{.Name}}", "--name", "SATA Controller", "--hostiocache", "on"]
  ]
  ssh_username = "root"
  shutdown_command = "shutdown -p +0"
}

build {
  name = "cerberus-builder"
  source "virtualbox-iso.dragonfly_base" {
    output_filename  = "cerberus-builder"
    output_directory = "cerberus-builder"
  }
  provisioner "shell" {
    script = "bootstrap/install-with-hammer2-to-disk.sh"
    execute_command = "chmod +x {{ .Path }}; env {{ .Vars }} {{ .Path }}"
  }
}
