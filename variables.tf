variable "name_vpc" {
  type    = string
  default = "mycloud-vpc"
}

variable "ami_id" {
  default = "ami-0f690b2f134c61108"
}
variable "cdir_block" {
  default = "172.22.0.0/16"
}

variable "vpc_name" {
  default = "mycloud-vpc"
}

variable "availability_zone" {
  default = [
    "us-east-1a",
    "us-east-1b",
    "us-east-1c"
  ]
}

