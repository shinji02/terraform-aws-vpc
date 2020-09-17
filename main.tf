### Module Main

provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "vpc" {
  cidr_block           = var.cdir_block
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name : var.name_vpc
    Terraform : true,
    Owner : "jovannserreau@gmail.com"
  }
}

resource "aws_subnet" "subnet_public" {
  count                   = length(var.availability_zone)
  cidr_block              = cidrsubnet(var.cdir_block, 4, (15 - count.index))
  availability_zone       = var.availability_zone[count.index]
  map_public_ip_on_launch = true
  vpc_id                  = aws_vpc.vpc.id
  tags = {
    Name = "${var.name_vpc}-public-${var.availability_zone[count.index]}"
    Tier = "public"
  }
}

resource "aws_subnet" "subnet_private" {
  count             = length(var.availability_zone)
  cidr_block        = cidrsubnet(var.cdir_block, 4, (6 - count.index))
  availability_zone = var.availability_zone[count.index]
  vpc_id            = aws_vpc.vpc.id
  tags = {
    Name = "${var.name_vpc}-private-${var.availability_zone[count.index]}"
    Tier = "private"
  }
}

resource "aws_internet_gateway" "default" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "${var.name_vpc}-igw"
  }
}
resource "aws_security_group" "nat" {
  tags = {
    Name = "${var.name_vpc}-group-vpc"
  }
  ingress {
    from_port   = 22
    protocol    = "tcp"
    to_port     = 22
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = [var.cdir_block]
  }

  ingress {
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
    cidr_blocks = ["172.22.0.0/16"]
  }

  egress {
    from_port   = 22
    protocol    = "tcp"
    to_port     = 22
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    protocol    = "-1"
    to_port     = 0
    cidr_blocks = ["0.0.0.0/0"]
  }

  vpc_id = aws_vpc.vpc.id
}

resource "aws_key_pair" "key" {
  key_name   = "${var.name_vpc}-key"
  public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCgb4KJX+Rtdm4rfAllGeviFxt1ONlj8zwbHaaoCIbpBr52re3xT1LND/tiQyool0qL9iZQIjd89//EPXNzlvNPXM+XJhN5A2zgTmHanAoJt+6N6LDJRCUYfRI9ooJzkWsraB7IqAPe1/lxb8OH0LZjS+OYoGn/0zVzlEeKZlSJSSf+GF98AHKcWxvUVpU/E++Q7fmsHdCCYDzxf6SGpUzgVC+WiIJN/u+c2uAIF0ZJ/mdgBZhOi85ISuVfnXeYKvxVfZry7jsLjVCJrLOBBdWCY5twHgsCdjKWDqkfVRVNoam/2e+QKsJnyxg8ajlYLVrQCiIXgf9S6KjMc4VtvOqP"
}

data "aws_ami" "ami" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["amzn-ami-vpc-nat-hvm-2018.03.0.20181116-x86_64-ebs"]
  }
}


resource "aws_instance" "nat" {
  count                  = length(aws_subnet.subnet_private)
  ami                    = data.aws_ami.ami.id
  availability_zone      = var.availability_zone[count.index]
  instance_type          = "t2.micro"
  key_name               = aws_key_pair.key.key_name
  vpc_security_group_ids = [aws_security_group.nat.id]
  subnet_id              = aws_subnet.subnet_public[count.index].id
  source_dest_check      = false
  tags = {
    Name = "${var.name_vpc}-nat-${var.availability_zone[count.index]}"
  }
}

resource "aws_eip" "eip" {
  count = length(aws_instance.nat)
  vpc   = true
}
resource "aws_eip_association" "a" {
  count         = length(aws_eip.eip)
  instance_id   = aws_instance.nat[count.index].id
  allocation_id = aws_eip.eip[count.index].id
}

resource "aws_route_table" "table-public" {
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name : "${var.name_vpc}-public"
  }
}

resource "aws_route" "route-public" {
  route_table_id         = aws_route_table.table-public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.default.id
}

resource "aws_route_table_association" "route-association-public" {
  count          = length(aws_subnet.subnet_public)
  subnet_id      = aws_subnet.subnet_public[count.index].id
  route_table_id = aws_route_table.table-public.id
}

resource "aws_route_table" "private_routable" {
  count  = length(aws_subnet.subnet_private)
  vpc_id = aws_vpc.vpc.id
  tags = {
    Name = "${var.name_vpc}-private-${aws_subnet.subnet_private[count.index].availability_zone}"
  }
}
resource "aws_route_table_association" "private_subnet_table_association" {
  count          = length(aws_subnet.subnet_private)
  subnet_id      = aws_subnet.subnet_private[count.index].id
  route_table_id = aws_route_table.private_routable[count.index].id
}
resource "aws_route" "private_subnet_route" {
  count                  = length(aws_subnet.subnet_private)
  route_table_id         = aws_route_table.private_routable[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  instance_id            = aws_instance.nat[count.index].id
}