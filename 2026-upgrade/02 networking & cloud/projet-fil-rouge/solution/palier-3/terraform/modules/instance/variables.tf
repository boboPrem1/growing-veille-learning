variable "nom" {
  type = string
}
variable "role" {
  type        = string
  description = "passerelle, lb, dns, app, db… (étiquette « role »)"
}
variable "image" {
  type    = string
  default = "marche-net/ubuntu:24.04"
}
variable "interfaces" {
  description = "Une par réseau : le réseau Docker, l'adresse attribuée, le sous-réseau et le nom d'interface voulu"
  type = list(object({
    reseau      = string
    ipv4        = string
    sous_reseau = string
    nom         = string
  }))
}
variable "demarrage" {
  type        = string
  description = "Le script de démarrage (user data)"
  sensitive   = true
}
variable "fichiers" {
  type        = map(string)
  description = "Fichiers déposés à la création : chemin → contenu"
  default     = {}
  sensitive   = true
}
variable "etiquettes" {
  type        = map(string)
  description = "Étiquettes de coût (equipe, env, region…)"
  default     = {}
}
variable "volumes" {
  type        = map(string)
  description = "Données persistantes : chemin dans la machine → nom du volume (qui survit au remplacement)"
  default     = {}
}
