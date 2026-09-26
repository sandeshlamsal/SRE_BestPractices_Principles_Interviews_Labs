output "resource_group" { value = azurerm_resource_group.lab.name }
output "cluster_name" { value = azurerm_kubernetes_cluster.lab.name }
output "get_credentials" {
  value = "az aks get-credentials -g ${azurerm_resource_group.lab.name} -n ${azurerm_kubernetes_cluster.lab.name} --context ${var.prefix}-aks"
}
