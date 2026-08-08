data "aws_availability_zones" "available" {
  state = "available"
}


resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr

  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-vpc"
    }
  )
}


resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-igw"
    }
  )
}


resource "aws_subnet" "public" {
  count = length(var.availability_zones)

  vpc_id = aws_vpc.this.id

  cidr_block = var.public_subnet_cidrs[count.index]

  availability_zone = var.availability_zones[count.index]

  map_public_ip_on_launch = true

  tags = merge(
    var.common_tags,
    {
      Name                     = "${var.project_name}-public-${var.availability_zones[count.index]}"
      "kubernetes.io/role/elb" = "1"
    }
  )
}


resource "aws_subnet" "private" {
  count = length(var.availability_zones)

  vpc_id = aws_vpc.this.id

  cidr_block = var.private_subnet_cidrs[count.index]

  availability_zone = var.availability_zones[count.index]

  map_public_ip_on_launch = false

  tags = merge(
    var.common_tags,
    {
      Name                              = "${var.project_name}-private-${var.availability_zones[count.index]}"
      "kubernetes.io/role/internal-elb" = "1"
    }
  )
}


resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-public-rt"
    }
  )
}


resource "aws_route" "public_internet" {
  route_table_id = aws_route_table.public.id

  destination_cidr_block = "0.0.0.0/0"

  gateway_id = aws_internet_gateway.this.id
}


resource "aws_route_table_association" "public" {
  count = length(var.availability_zones)

  subnet_id = aws_subnet.public[count.index].id

  route_table_id = aws_route_table.public.id
}


resource "aws_eip" "nat" {
  count = var.enable_nat_gateway ? (
    var.single_nat_gateway ? 1 : length(var.availability_zones)
  ) : 0

  domain = "vpc"

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-nat-eip-${count.index + 1}"
    }
  )
}


resource "aws_nat_gateway" "this" {
  count = var.enable_nat_gateway ? (
    var.single_nat_gateway ? 1 : length(var.availability_zones)
  ) : 0

  allocation_id = aws_eip.nat[count.index].id

  subnet_id = aws_subnet.public[
    var.single_nat_gateway ? 0 : count.index
  ].id

  depends_on = [
    aws_internet_gateway.this
  ]

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-nat-${count.index + 1}"
    }
  )
}


resource "aws_route_table" "private" {
  count = length(var.availability_zones)

  vpc_id = aws_vpc.this.id

  tags = merge(
    var.common_tags,
    {
      Name = "${var.project_name}-private-${var.availability_zones[count.index]}-rt"
    }
  )
}


resource "aws_route" "private_nat" {
  count = var.enable_nat_gateway ? length(var.availability_zones) : 0

  route_table_id = aws_route_table.private[count.index].id

  destination_cidr_block = "0.0.0.0/0"

  nat_gateway_id = aws_nat_gateway.this[
    var.single_nat_gateway ? 0 : count.index
  ].id
}


resource "aws_route_table_association" "private" {
  count = length(var.availability_zones)

  subnet_id = aws_subnet.private[count.index].id

  route_table_id = aws_route_table.private[count.index].id
}
