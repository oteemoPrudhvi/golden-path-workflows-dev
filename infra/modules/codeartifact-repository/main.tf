resource "aws_codeartifact_repository" "this" {
  repository   = var.repository
  domain       = var.domain
  domain_owner = var.domain_owner
  description  = var.description != "" ? var.description : "Repository ${var.repository}"

  dynamic "upstream" {
    for_each = var.upstreams

    content {
      repository_name = upstream.value
    }
  }

  tags = var.tags
}
