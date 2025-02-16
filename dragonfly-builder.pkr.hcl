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
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1"
    }
  }
}
variable "debug" {
  default = false
  type = bool
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

variable "ami_tags" {
  type = map(string)
  default = {}
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
  headless = ! var.debug
  guest_os_type = "FreeBSD_64"
  cpus = var.cpus
  memory= var.memory
  rtc_time_base = "UTC"
  firmware = "efi"

  format = "ova"

  virtualbox_version_file = ""
  # Dragonfly does not support guest additions and
  guest_additions_mode = "disable"

  gfx_vram_size = 16
  gfx_controller = "vmsvga"

  iso_url       = "dfly-x86_64-6.4.0_REL.iso"
  iso_checksum  = "md5:ff4d500c7c75b1f88ca4237a6aa861d1"

  chipset = "ich9"
  iso_interface = "sata"
  nic_type = "virtio"
  hard_drive_interface = "pcie"

  sata_port_count = 4
  disk_size = var.disk_size_gb * 1024
  # SSD mode:
  hard_drive_nonrotational = true
  hard_drive_discard = true

  cd_files = ["bootstrap/*"]
  cd_content = {
    "root.pub" = data.sshkey.install.public_key
    "pfi.conf" = <<EOF
ifconfig_vtnet0="DHCP"
pfi_script="unattended-init.sh"
pfi_sshd_permit_root_login="YES"
# pfi_autologin="root"
pfi_shutdown_command="shutdown -r now"
pfi_sshd_permit_root_login="YES"
pfi_sshd_permit_empty_passwords="YES"
pfi_rc_actions="netif dhcp_client sshd"

EOF
  }
  cd_label = "init-data"


  nested_virt = true
  usb = true

  boot_wait = "5s"

  ssh_private_key_file      = data.sshkey.install.private_key_path
  ssh_clear_authorized_keys = false  # we don't have `sudo` on the ISO...
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
    "<wait50ms>1<enter><wait70s>",
  ]
  vboxmanage = [
    [ "setextradata", "{{.Name}}", "GUI/ScaleFactor", "1.7" ],
    [ "modifyvm", "{{.Name}}", "--firmware", "EFI" ],
    [ "modifyvm", "{{.Name}}", "--hpet", "on" ],
    [ "modifyvm", "{{.Name}}", "--x2apic", "on" ],
    [ "modifyvm", "{{.Name}}", "--vtxux", "on" ],
    [ "modifyvm", "{{.Name}}", "--accelerate3d", "on" ],
    # [ "modifyvm", "{{.Name}}", "--accelerate2dvideo", "on" ],
    [ "modifyvm", "{{.Name}}", "--nat-localhostreachable1", "on" ],
    [ "storagectl",  "{{.Name}}", "--name", "SATA Controller", "--hostiocache", "off"],
    [ "storagectl",  "{{.Name}}", "--name", "NVMe Controller", "--hostiocache", "off"]
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
      "bootstrap/packages.txt",
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
      "./install-dragonfly.sh",
    ]
    execute_command = "chmod +x {{ .Path }}; env {{ .Vars }} {{ .Path }}"
  }

  post-processor "checksum" { # checksum image
    checksum_types = [ "md5", "sha512" ] # checksum the artifact
    keep_input_artifact = true           # keep the artifact
  }
}
