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
    ]
    type = list(string)
}

data "sshkey" "image" {
  type = "ed25519"
}

source "virtualbox-ovf" "cerberus-image" {
  source_path = "cerberus-builder/cerberus-builder.ovf"
  # headless = true

  ssh_private_key_file      = data.sshkey.image.private_key_path
  ssh_clear_authorized_keys = true
  http_content = {
    "/root.pub" = data.sshkey.image.public_key
    "/setup-user.sh" = file("bootstrap/setup-user.sh")
    "/rc.conf" = templatefile("config/rc.tmpl.conf", {
      external_address = var.external_address
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
    [ "setextradata", "{{.Name}}", "GUI/ScaleFactor", "1.7" ],
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

  # ARJ: What we'll do is
  # make a USB image via /usr/src/nrelease,
  # then mount it via vnconfig and copy in additional configuration files
  # then we will use the files directive to copy the img out of the vm,
  # and use a dd command to burn a USB image for booting.
  provisioner "shell" {
    inline = [
      "cd /usr/src/nrelease && make -D DPORTS_EXTRA_PACKAGES='${ join(" ", var.packages) }' binpkgs check clean buildworld1 buildkernel1 buildiso customizeiso pkgs srcs",
      "pushd root/etc",
      "curl http://{{.HTTPIP}}:{{.HTTPPort}}/rc.conf > rc.conf",
      "popd"
    ]
    remote_folder = "/home/packer"
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
  provisioner "shell" {
    inline = [
      "cd /usr/src/nrelease && make -D mkimg",
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
