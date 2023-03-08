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

variable "hostname" {
  type = string
}

variable "external_address" {
  type = string
}

variable "domain" {
  type = string
}

variable "external_router_address" {
  type = string
}

variable "packages" {
    default = [
      "dns/bind918",
      "shells/bash",
      "sysutils/py-supervisor",
      "lang/python311",
      "net/samba413",
    ]
    type = list(string)
}

data "sshkey" "image" {
  type = "ed25519"
}

source "virtualbox-ovf" "cerberus-image" {
  source_path = "dragonfly/dragonfly.ovf"
  headless = true

  ssh_private_key_file      = data.sshkey.image.private_key_path
  ssh_clear_authorized_keys = true
  http_content = {
    "/root.pub" = data.sshkey.image.public_key
    "/setup-user.sh" = file("bootstrap/setup-user.sh")
    "/rc.conf" = templatefile("config/rc.tmpl.conf", {
      external_address = var.external_address
      external_router_address = var.external_router_address
      hostname = var.hostname
      domain = var.domain
    })
  }

  boot_command  = [
    # "<esc><wait150ms>",
    # "fs1:", # Switch to the Optical CD drive and boot
    # "<enter>",
    # "\\efi\\boot\\bootx64.efi", # Initiate the EFI boot loader
    # "<enter>",
    "<wait1s>",
    "<return><wait37s>",
    "root<return>",
    "curl 'http://{{ .HTTPIP }}:{{ .HTTPPort }}/setup-user.sh' | sh -s {{ .HTTPIP }} {{ .HTTPPort }} root && \\<return>",
    # "tail -f /var/log/auth.log<return>",
    "exit <return>",
  ]
  vboxmanage = [
    [ "modifyvm", "{{.Name}}", "--nat-localhostreachable1", "on" ],
  ]

  ssh_username = "root"
  shutdown_command = "shutdown -p now"
}

build {
  name = "cerberus-image"
  source "virtualbox-ovf.cerberus-image" {
      skip_export = true
  }
  # Uploda modified nrelease script as we're making a liveusb
  # with a custom configuration:
  provisioner "file" {
    destination = "/usr/src/nrelease/Makefile.cerberus"
    source      = "config/Makefile.cerberus"
  }
  provisioner "shell" {
    inline = [
      "pushd /usr/src/nrelease",
        "DPORTS_EXTRA_PACKAGES=\"${ join(" ", var.packages) }\"",
        "make -f Makefile.cerberus -DWITHOUT_SRCS build",
        "pushd root/etc",
          "curl http://{{.HTTPIP}}:{{.HTTPPort}}/rc.conf > rc.conf",
        "popd",
      "popd"
    ]
    inline_shebang = "/usr/bin/env bash -xe"
    remote_folder = "/root"
  }
  # copy files into the new usb image root
  provisioner "file" {
    destination = "/usr/obj/release/root/etc"
    sources     = [
      "config/pf.conf",
      "config/syslog.conf",
      "config/newsyslog.conf",
    ]
  }
  provisioner "file" {
    destination = "/etc/.gitignore"
    source = "config/etc.gitignore"
  }
  provisioner "file" {
    destination = "/usr/local/etc/.gitignore"
    source = "config/usr_local_etc.gitignore"
  }
  provisioner "shell" {
    inline = [
      "cd /usr/src/nrelease && make image",
    ]
    remote_folder = "/root"
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
