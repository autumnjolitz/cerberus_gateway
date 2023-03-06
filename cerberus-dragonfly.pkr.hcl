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


variable "packer_password" {
    sensitive = true
    default = "packer321"
    type = string
}
variable "root_password" {
    sensitive = true
    default = "$rootyFru1ty!167"
    type = string
}



data "sshkey" "install" {
}

source "virtualbox-iso" "dragonfly_base" {
  guest_os_type = "FreeBSD_64"
  cpus = 2
  memory= 2048
  firmware = "efi"

  iso_url       = "http://mirror-master.dragonflybsd.org/iso-images/dfly-x86_64-6.0.1_REL.iso"
  iso_checksum  = "md5:a27b7e980e84b67251c3f40e9a22a846"

  boot_wait     = "2s"

  chipset = "ich9"
  iso_interface = "sata"
  hard_drive_interface = "sata"

  sata_port_count = 2
  disk_size = 68000

  hard_drive_nonrotational = true
  hard_drive_discard = true

  ssh_private_key_file      = data.sshkey.install.private_key_path
  ssh_clear_authorized_keys = true
  http_content = {
    "/ssh.pub" = data.sshkey.install.public_key
    "/init.sh" = file("bootstrap/init.sh")

  }

  boot_command  = [
    # "<esc><wait150ms>",
    # "fs1:", # Switch to the Optical CD drive and boot
    # "<enter>",
    # "\\efi\\boot\\bootx64.efi", # Initiate the EFI boot loader
    # "<enter>",
    "<wait1s>",
    "<return><wait69s>",
    "root<return>",
    "sh <return>",  # Switch to bourne shell (not csh)
    "export ROOT_PASSWORD='${var.root_password}' <return>",
    "export PACKER_USER_PASSWORD='${var.packer_password}' <return>",
    "export HTTP_SERVER='http://{{ .HTTPIP }}:{{ .HTTPPort }}' <return>",
    "dhclient em0 && sleep 3 && \\<return>", # Get the ip from the dhcp server
    "fetch $HTTP_SERVER/init.sh && \\<return>",
    "chmod +x init.sh && \\<return>",
    "./init.sh && shutdown -r +0 <return>",
    "<wait120s>",
    "<return>",
  ]
  vboxmanage = [
   ["setextradata", "{{.Name}}", "GUI/ScaleFactor", "1.7"],
   [ "modifyvm", "{{.Name}}", "--firmware", "EFI" ],
  ]

  ssh_username = "packer"
  shutdown_command = "echo ${var.packer_password} | sudo -S shutdown -p now"
}

build {
  name = "cerberus-base"
  source "virtualbox-iso.dragonfly_base" {
      skip_export = true
  }
  # ARJ: What we'll do is
  # make a USB image via /usr/src/nrelease,
  # then mount it via vnconfig and copy in additional configuration files
  # then we will use the files directive to copy the img out of the vm,
  # and use a dd command to burn a USB image for booting.
  provisioner "shell" {
    inline = [
      "echo ${var.packer_password} | sudo -S -D /usr/src/nrelease make -D binpkgs check clean buildworld1 buildkernel1 buildiso customizeiso pkgs srcs",
      # move the etc files into place
      # do the configuration here or something
      "echo ${var.packer_password} | sudo -S -D /usr/src/nrelease make -D mkimg",
    ]
    remote_folder = "/home/packer"
  }
  # copy files into the new usb image root
  provisioner "file" {
    destination = "/usr/obj/release/root/etc"
    sources     = [
      "config/pf.conf",
      "config/rc.conf",
      "config/syslog.conf",
      "config/newsyslog.conf",
    ]
  }
  provisioner "shell" {
    inline = [
      "echo ${var.packer_password} | sudo -S -D /usr/src/nrelease make -D mkimg",
    ]
    remote_folder = "/home/packer"
  }
  provisioner "file" {
    destination = "."
    source      = "/usr/obj/release/dfly.img"
    direction   = "download"
  }
  post-processor "artifice" {
    files = ["dfly.img"]
  }
  post-processor "checksum" {
    checksum_types = ["sha1", "sha256"]
    output = "{{.BuildName}}_{{.ChecksumType}}.checksum"
    keep_input_artifact = true
  }
}
