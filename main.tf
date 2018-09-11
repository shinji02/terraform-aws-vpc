### Backend definition

terraform {
  # The configuration for this backend will be filled in by Terragrunt
  backend "s3" {}
}

### Module Main

########################################################################################################################
### Step 1 - VPC
########################################################################################################################

resource "aws_vpc" "vpc" {
  cidr_block           = "${var.cidr}"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = "${merge(var.tags, map("Name", format("%s-vpc", var.name)))}"
}

########################################################################################################################
### Step 2 & 3 - AZS and Subnets
########################################################################################################################

# Create private subnets (1 per AZ)
resource "aws_subnet" "private" {
  count             = "${length(var.azs)}"
  vpc_id            = "${aws_vpc.vpc.id}"
  cidr_block        = "${cidrsubnet("${var.cidr}", 4, count.index)}"
  availability_zone = "${element(var.azs, count.index)}"

  tags = "${merge(var.tags,
    map("Name", format("%s-private-%s", var.name, element(var.azs, count.index))),
    map("Tier", "private"))}"
}

# Create public subnets (1 per AZ)
resource "aws_subnet" "public" {
  count                   = "${length(var.azs)}"
  vpc_id                  = "${aws_vpc.vpc.id}"
  cidr_block              = "${cidrsubnet("${var.cidr}", 4, 15 - count.index)}"
  availability_zone       = "${element(var.azs, count.index)}"
  map_public_ip_on_launch = true

  tags = "${merge(var.tags,
    map("Name", format("%s-public-%s", var.name, element(var.azs, count.index))),
    map("Tier", "public"))}"
}

########################################################################################################################
### Step 4 - Gateways
########################################################################################################################

# Create Internet gateway
resource "aws_internet_gateway" "igw" {
  vpc_id = "${aws_vpc.vpc.id}"
  tags   = "${merge(var.tags, map("Name", format("%s-igw", var.name)))}"
}

# Create NAT Gateway Instances - manual method
data "aws_ami" "nat" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn-ami-vpc-nat-hvm-*-x86_64-ebs"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_key_pair" "nat" {
  count      = "${var.enable_managed_nat ? 0 : 1}"
  key_name   = "ops"
  public_key = "${var.public_key}"
}

resource "aws_instance" "nat" {
  count             = "${length(var.azs) * (var.enable_managed_nat ? 0 : 1)}"
  subnet_id         = "${element(aws_subnet.public.*.id, count.index)}"
  ami               = "${data.aws_ami.nat.id}"
  key_name          = "${aws_key_pair.nat.key_name}"
  instance_type     = "t2.micro"
  source_dest_check = false
  tags              = "${merge(var.tags,
    map("Name", format("%s-nat-%s", var.name, element(var.azs, count.index))))}"

  depends_on = ["aws_internet_gateway.igw", "aws_route_table_association.public"]
}

resource "aws_eip" "nat" {
  count = "${length(var.azs)}"
  vpc   = true
}

resource "aws_eip_association" "nat" {
  count         = "${length(var.azs) * (var.enable_managed_nat ? 0 : 1)}"
  instance_id   = "${element(aws_instance.nat.*.id, count.index)}"
  allocation_id = "${element(aws_eip.nat.*.id, count.index)}"
}

# Create Managed NAT Gateway - managed method
resource "aws_nat_gateway" "nat" {
  count         = "${length(var.azs) * (var.enable_managed_nat ? 1 : 0)}"
  allocation_id = "${element(aws_eip.nat.*.id, count.index)}"
  subnet_id     = "${element(aws_subnet.public.*.id, count.index)}"
  depends_on    = ["aws_internet_gateway.igw"]
}

########################################################################################################################
### Step 5 - Route tables
########################################################################################################################

# Create public route table (1 for all AZs)
resource "aws_route_table" "public" {
  vpc_id = "${aws_vpc.vpc.id}"
  tags   = "${merge(var.tags,
    map("Name", format("public-%s", substr(element(var.azs, 0), 0, length(element(var.azs, 0)) -1))))}"
}

# Create routes for public route table
# 0.0.0.0/0 pointing to the igw (enable communication with Internet)
resource "aws_route" "public_igw_world" {
  route_table_id         = "${aws_route_table.public.id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.igw.id}"
}

# Create private route table (1 per AZ)
resource "aws_route_table" "private" {
  count  = "${length(var.azs)}"
  vpc_id = "${aws_vpc.vpc.id}"
  tags   = "${merge(var.tags,
    map("Name", format("private-%s", element(var.azs, count.index))))}"
}

# Create routes for private route table
# 0.0.0.0/0 should go through Managed Nat in order to enable Internet access
resource "aws_route" "private_managed_ngw_world" {
  count                  = "${length(var.azs) * (var.enable_managed_nat ? 1 : 0)}"
  route_table_id         = "${element(aws_route_table.private.*.id, count.index)}"
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = "${element(aws_nat_gateway.nat.*.id, count.index)}"
}

# 0.0.0.0/0 should go through Instance Nat in order to enable Internet access
resource "aws_route" "private_instance_ngw_world" {
  count                  = "${length(var.azs) * (var.enable_managed_nat ? 0 : 1)}"
  route_table_id         = "${element(aws_route_table.private.*.id, count.index)}"
  destination_cidr_block = "0.0.0.0/0"
  instance_id            = "${element(aws_instance.nat.*.id, count.index)}"
}

# Associate route table with subnets

resource "aws_route_table_association" "public" {
  count          = "${length(var.azs)}"
  subnet_id      = "${element(aws_subnet.public.*.id, count.index)}"
  route_table_id = "${aws_route_table.public.id}"
}

resource "aws_route_table_association" "private" {
  count          = "${length(var.azs)}"
  subnet_id      = "${element(aws_subnet.private.*.id, count.index)}"
  route_table_id = "${element(aws_route_table.private.*.id, count.index)}"
}
