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


variable "packages" {
    default = [
      "dns/bind918",
    ]
    type = list(string)
}




data "sshkey" "install" {
}

source "virtualbox-ovf" "cerberus-image" {
  source_path = "cerberus-builder/cerberus-builder.ovf"

  ssh_private_key_file      = data.sshkey.install.private_key_path
  ssh_clear_authorized_keys = true
  http_content = {
    "/ssh.pub" = data.sshkey.install.public_key
    "/setup-packer-user.sh" = file("bootstrap/setup-packer-user.sh")
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
    "sh <return>",  # Switch to bourne shell (not csh)
    "export HTTP_SERVER='http://{{ .HTTPIP }}:{{ .HTTPPort }}' <return>",
    "fetch $HTTP_SERVER/setup-packer-user.sh && \\<return>",
    "chmod +x setup-packer-user.sh && \\<return>",
    "./setup-packer-user.sh $HTTP_SERVER && exit",
    "<return>",
  ]
  vboxmanage = [
    [ "setextradata", "{{.Name}}", "GUI/ScaleFactor", "1.7" ],
    [ "modifyvm", "{{.Name}}", "--nat-localhostreachable1", "on" ],
  ]

  ssh_username = "packer"
  shutdown_command = "sudo shutdown -p now"
}

build {
  name = "cerberus-build"
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
      "cd /usr/src/nrelease && sudo make -D DPORTS_EXTRA_PACKAGES='${ join(" ", var.packages) }' binpkgs check clean buildworld1 buildkernel1 buildiso customizeiso pkgs srcs",
      # move the etc files into place
      # do the configuration here or something
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
      "sudo -S -D /usr/src/nrelease make -D mkimg",
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