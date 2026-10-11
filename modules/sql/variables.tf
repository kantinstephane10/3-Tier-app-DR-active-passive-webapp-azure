variable "name" {
  type = string
}
variable "primary_rg" {
  type = string
}
variable "secondary_rg" {
  type = string
}
variable "primary_location" {
  type = string
}
variable "secondary_location" {
  type = string
}
variable "enable_secondary" {
  type = bool
}
variable "admin_login" {
  type = string
}
variable "admin_object_id" {
  type = string
}
variable "tenant_id" {
  type = string
}
variable "sku" {
  type = string
}
variable "zone_redundant" {
  type = bool
}
variable "tags" {
  type = map(string)
}
