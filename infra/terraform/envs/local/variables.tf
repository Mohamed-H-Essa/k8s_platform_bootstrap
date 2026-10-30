variable "cluster_name" {
  description = "kind cluster name (nodes are <name>-control-plane, <name>-worker, <name>-worker2)."
  type        = string
  default     = "slipway"
}

variable "node_image" {
  description = "kindest/node image, pinned by digest (the one kind v0.31 ships with)."
  type        = string
  default     = "kindest/node:v1.35.0@sha256:452d707d4862f52530247495d180205e029056831160e22870e37e3f6c1ac31f"
}

variable "docker_host" {
  description = "Docker socket. The Makefile passes the active docker context's endpoint (OrbStack, Docker Desktop, Colima)."
  type        = string
  default     = "unix:///var/run/docker.sock"
}

variable "http_port" {
  description = "Host port for http://*.localtest.me (the gateway)."
  type        = number
  default     = 80
}

variable "git_server_image" {
  description = "soft-serve, the small Git server Argo CD syncs from."
  type        = string
  default     = "charmcli/soft-serve:v0.12.4"
}

variable "git_admin_public_key" {
  description = "Public key allowed to push to the Git server (the Makefile generates .local/git_ed25519)."
  type        = string
}

variable "git_repo_url" {
  description = "Where Argo CD reads the platform from, as seen from inside the cluster."
  type        = string
  default     = "http://slipway-git:23232/platform.git"
}

variable "git_revision" {
  type    = string
  default = "main"
}

variable "argocd_chart_version" {
  type    = string
  default = "10.11.6"
}

variable "argocd_apps_chart_version" {
  type    = string
  default = "2.0.7"
}
