variable "aws_region" {
  type    = string
  default = "us-east-1"
}
variable "project_name" {
  type    = string
  default = "silipos-preview"
}
variable "instance_type" {
  type    = string
  default = "t3.micro"
}
variable "allowed_cidr" {
  description = "Your public IPv4 CIDR, usually x.x.x.x/32; allows SSH and HTTP preview access."
  type        = string
  validation {
    condition     = can(cidrnetmask(var.allowed_cidr)) && !endswith(var.allowed_cidr, "/0")
    error_message = "Provide a restricted IPv4 CIDR, not 0.0.0.0/0."
  }
}
variable "ssh_public_key_path" {
  description = "Path to an existing SSH public key. Private keys stay on your computer."
  type        = string
}
