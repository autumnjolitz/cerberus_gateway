packer {
  required_plugins {
    virtualbox = {
      version = ">= 1.0.4"
      source  = "github.com/hashicorp/virtualbox"
    }
    sshkey = {
      version = ">= 1.0.8"
      source = "github.com/ivoronin/sshkey"
    }

  }
}
# ARJ: Dragonfly's HAMMER2 likes 60+GiB disks
variable "disk_size_gb" {
    default = 60
    type = number
  validation {
    condition = var.disk_size_gb >= 60
    error_message = "HAMMER2 does not accept disk sizes smaller than 60GiB!"
  }
}

variable "cpus" {
  default = 4
  type = number
  validation {
      condition = var.cpus > 0
      error_message = "CPU count must be > 0."
  }
}

variable "memory" {
  default = 4096
  type = number
  validation {
      condition = var.memory >= 1024
      error_message = "Memory MiB must be > 1024."
  }
}

data "sshkey" "install" {
  type = "ed25519"
}

source "virtualbox-iso" "dragonfly" {
  headless = true
  guest_os_type = "FreeBSD_64"
  cpus = var.cpus
  memory= var.memory
  rtc_time_base = "UTC"
  firmware = "efi"

  virtualbox_version_file = ""
  guest_additions_mode = "disable"

  gfx_vram_size = 16
  gfx_controller = "vmsvga"

  iso_url       = "dfly-x86_64-6.4.0_REL.iso"
  iso_checksum  = "md5:ff4d500c7c75b1f88ca4237a6aa861d1"

  chipset = "ich9"
  iso_interface = "sata"
  hard_drive_interface = "sata"

  sata_port_count = 4
  disk_size = var.disk_size_gb * 1024

  hard_drive_nonrotational = true
  hard_drive_discard = true
  nested_virt = true
  usb = true

  boot_wait = "90s"

  ssh_private_key_file      = data.sshkey.install.private_key_path
  ssh_clear_authorized_keys = false
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
    "root<return>",
    "dhclient em0 && sleep 3 && \\<return>", # Get the ip from the dhcp server
    "curl 'http://{{ .HTTPIP }}:{{ .HTTPPort }}/setup-user.sh' | sh -s {{ .HTTPIP }} {{ .HTTPPort }} root && \\<return>",
    # "tail -f /var/log/auth.log<return>",  # ARJ: Uncomment this to debug SSH login errors
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
  name = "dragonfly-builder"
  source "virtualbox-iso.dragonfly" {
    output_filename  = "dragonfly"
    output_directory = "dragonfly"
  }
  provisioner "shell" {
    inline = [
      # Setup the installer directory
      "mkdir -p /root/installer /root/installer/post-install",
    ]
    execute_command = "chmod +x {{ .Path }}; env {{ .Vars }} {{ .Path }}"
  }

  provisioner "file" {
    destination = "/root/installer/"
    sources = [
      "bootstrap/common.sh",
      "bootstrap/install-dragonfly.sh",
    ]
  }
  provisioner "file" {
    destination = "/root/installer/post-install/"
    sources = [
      "bootstrap/post-install/00-after-dragonfly-install.sh",
      "bootstrap/post-install/01-custom.sh",
    ]
  }
  provisioner "shell" {
    inline = [
      "cd /root/installer",
      "chmod +x install-dragonfly.sh",
      "./install-dragonfly.sh /dev/da0",
    ]
    execute_command = "chmod +x {{ .Path }}; env {{ .Vars }} {{ .Path }}"
  }
}
