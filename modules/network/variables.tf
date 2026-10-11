variable "name" {
  type = string
}
variable "resource_group_name" {
  type = string
}
variable "location" {
  type = string
}
variable "tags" {
  type = map(string)
}
variable "cidr" {
  type = string
}
variable "enable_nat" {
  type = bool
}

variable "remote_cidr" {
  type    = string
  default = null
}
