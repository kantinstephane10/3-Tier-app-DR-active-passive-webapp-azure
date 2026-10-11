variable "name" {
  type = string
}
variable "resource_group_name" {
  type = string
}
variable "regions" {
  type = map(object({ location = string, resource_group_name = string, subnet_id = string, vnet_id = string, server_id = string }))
}
variable "tags" {
  type = map(string)
}
