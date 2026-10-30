output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.this.id
}

output "private_subnet_ids" {
  description = "Private subnets (nodes, pods, internal load balancers), in AZ order."
  value       = [for az in var.azs : aws_subnet.private[az].id]
}

output "public_subnet_ids" {
  description = "Public subnets (NAT gateway, internet-facing load balancers), in AZ order."
  value       = [for az in var.azs : aws_subnet.public[az].id]
}

output "nat_public_ips" {
  description = "Elastic IPs of the NAT gateway(s): the address the cluster's outbound traffic comes from."
  value       = [for eip in aws_eip.nat : eip.public_ip]
}
