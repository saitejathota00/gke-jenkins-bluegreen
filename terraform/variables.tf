variable "project_id" {
  type = string
}

variable "region" {
  type    = string
  default = "asia-south1"
}

variable "zone" {
  type    = string
  default = "asia-south1-a"
}

variable "name" {
  type    = string
  default = "demo"
}

variable "node_machine_type" {
  type    = string
  default = "e2-standard-2"
}

