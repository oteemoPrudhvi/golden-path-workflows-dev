# =============================================================================
# NETWORK — VPC, subnets, NAT, routing
# =============================================================================
# Shared by both EKS clusters (Backstage and Argo Workflows). One VPC rather
# than two keeps the cross-cluster path simple: the Backstage Scaffolder has
# to reach the Argo server, and VPC peering for a demo would be needless work.
# The clusters stay separate; only the network is shared.
# =============================================================================

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  # /20 subnets out of a /16. Public subnets from the lower half, private from
  # the upper, so the two ranges stay visually distinct when debugging.
  public_subnets  = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i)]
  private_subnets = [for i in range(var.az_count) : cidrsubnet(var.vpc_cidr, 4, i + 8)]

  # Every cluster gets a shared-ownership tag on every subnet.
  cluster_subnet_tags = {
    for name in var.eks_cluster_names :
    "kubernetes.io/cluster/${name}" => "shared"
  }
}

resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr

  # Both required by EKS: pods get DNS, and the private hosted zone used by
  # RDS resolves inside the VPC.
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.tags, { Name = "${var.name_prefix}-vpc" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name_prefix}-igw" })
}

# --- Public subnets ----------------------------------------------------------
# Internet-facing ALBs live here. Nodes do not.
resource "aws_subnet" "public" {
  count = var.az_count

  vpc_id                  = aws_vpc.this.id
  cidr_block              = local.public_subnets[count.index]
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(
    var.tags,
    local.cluster_subnet_tags,
    {
      Name = "${var.name_prefix}-public-${local.azs[count.index]}"
      # Tells the AWS Load Balancer Controller to place internet-facing
      # load balancers in these subnets.
      "kubernetes.io/role/elb" = "1"
    },
  )
}

# --- Private subnets ---------------------------------------------------------
# EKS nodes and RDS. No route to the internet except via NAT.
resource "aws_subnet" "private" {
  count = var.az_count

  vpc_id            = aws_vpc.this.id
  cidr_block        = local.private_subnets[count.index]
  availability_zone = local.azs[count.index]

  # Explicit rather than relying on the AWS default. This is a security
  # property — nodes and RDS live here — so it should be stated in code where
  # a reviewer can see it, not inherited silently.
  map_public_ip_on_launch = false

  tags = merge(
    var.tags,
    local.cluster_subnet_tags,
    {
      Name = "${var.name_prefix}-private-${local.azs[count.index]}"
      # Internal load balancers go here.
      "kubernetes.io/role/internal-elb" = "1"
    },
  )
}

# --- NAT ---------------------------------------------------------------------
resource "aws_eip" "nat" {
  count  = var.single_nat_gateway ? 1 : var.az_count
  domain = "vpc"
  tags   = merge(var.tags, { Name = "${var.name_prefix}-nat-eip-${count.index}" })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  count = var.single_nat_gateway ? 1 : var.az_count

  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id

  tags = merge(var.tags, { Name = "${var.name_prefix}-nat-${count.index}" })

  depends_on = [aws_internet_gateway.this]
}

# --- Routing -----------------------------------------------------------------
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name_prefix}-rt-public" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count          = var.az_count
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# One route table per private subnet even with a single NAT, so switching
# single_nat_gateway to false later needs no restructuring.
resource "aws_route_table" "private" {
  count  = var.az_count
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = "${var.name_prefix}-rt-private-${local.azs[count.index]}" })
}

resource "aws_route" "private_nat" {
  count = var.az_count

  route_table_id         = aws_route_table.private[count.index].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = var.single_nat_gateway ? aws_nat_gateway.this[0].id : aws_nat_gateway.this[count.index].id
}

resource "aws_route_table_association" "private" {
  count          = var.az_count
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# --- S3 gateway endpoint -----------------------------------------------------
# Free, and keeps S3 traffic (TechDocs, Argo artifacts, ECR layers) off the NAT
# gateway. On a single-NAT demo this is the cheapest meaningful optimisation
# available — ECR image pulls alone would otherwise be billed as NAT data.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id

  tags = merge(var.tags, { Name = "${var.name_prefix}-vpce-s3" })
}

data "aws_region" "current" {}
