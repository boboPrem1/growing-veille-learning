# La couche « fondations » (Palier 3) : la LANDING ZONE. Avant qu'une équipe ne déploie quoi que ce
# soit, on lui ouvre un « compte » chez le fournisseur — ses buckets, ses identités — avec des règles
# communes que personne ne peut contourner : chaque équipe ne voit QUE ses ressources ; les ressources
# critiques (état Terraform, sauvegardes, journaux) sont protégées de la suppression pour TOUS ; une
# identité d'AUDIT, en lecture seule, voit tout (la sécurité, qui fait tourner la surveillance de
# conformité). Un nouveau compte = une entrée dans « comptes », pas une configuration à la main.
# (Chez AWS : Organizations + Control Tower, les SCP ; chez GCP : dossiers et politiques d'organisation.)

terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = { source = "hashicorp/aws", version = "6.66.0" }
  }
  backend "s3" {}
}

provider "aws" {
  region                      = "us-east-1"
  profile                     = "fournisseur"
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  endpoints {
    s3  = "https://s3.fournisseur.test"
    iam = "https://s3.fournisseur.test"
  }
}

locals {
  # les comptes d'équipe : un nom, une équipe, un environnement (le reste en découle)
  comptes = {
    prod = { equipe = "plateforme", env = "prod" }
    dev  = { equipe = "produit", env = "dev" }
  }
  # ce que PERSONNE ne doit pouvoir supprimer (vérifié par la surveillance de conformité)
  proteges = ["marche-etat-terraform", "marche-sauvegardes", "marche-journaux"]
}

# ------------------------------------------------------------------ un compte par équipe
resource "aws_s3_bucket" "donnees" {
  for_each = local.comptes
  bucket   = "marche-${each.key}-donnees"
  tags     = { compte = each.key, equipe = each.value.equipe, env = each.value.env, projet = "marche" }
}
resource "aws_s3_bucket_versioning" "donnees" {
  for_each = local.comptes
  bucket   = aws_s3_bucket.donnees[each.key].id
  versioning_configuration { status = "Enabled" }
}
resource "aws_iam_user" "deploiement" {
  for_each = local.comptes
  name     = "marche-${each.key}-deploiement"
  # (pas d'étiquettes ici : l'IAM de ce fournisseur ne les conserve pas — Terraform verrait une dérive
  #  permanente, et une dérive permanente masque les vraies. Les étiquettes vivent sur les buckets.)
}
resource "aws_iam_user_policy" "deploiement" {
  for_each = local.comptes
  name     = "perimetre-${each.key}"
  user     = aws_iam_user.deploiement[each.key].name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # tout, mais SEULEMENT sur ses propres ressources
      { Effect = "Allow", Action = ["s3:*"], Resource = ["arn:aws:s3:::marche-${each.key}-*", "arn:aws:s3:::marche-${each.key}-*/*"] },
      # déposer ses journaux dans le bucket central, sous son préfixe — sans pouvoir les relire ni effacer
      { Effect = "Allow", Action = ["s3:PutObject"], Resource = ["arn:aws:s3:::marche-journaux/${each.key}/*"] },
      # (le garde-fou commun — « jamais de suppression des ressources critiques » — serait ici un Deny
      #  explicite. Ce fournisseur n'accepte QUE « Allow » : le garde-fou, c'est le refus par défaut, et
      #  la surveillance de conformité qui vérifie qu'aucune identité n'a reçu ces droits. Chez AWS, une
      #  SCP « Deny » l'emporterait sur tout « Allow » accordé plus tard par erreur.)
    ]
  })
}
resource "aws_iam_access_key" "deploiement" {
  for_each = local.comptes
  user     = aws_iam_user.deploiement[each.key].name
}

# ------------------------------------------------------------------ le compte « sécurité »
resource "aws_s3_bucket" "journaux" {
  bucket = "marche-journaux"
  tags   = { compte = "securite", equipe = "securite", env = "prod", projet = "marche" }
}
resource "aws_s3_bucket_versioning" "journaux" {
  bucket = aws_s3_bucket.journaux.id
  versioning_configuration { status = "Enabled" } # un journal ne s'écrase pas
}
resource "aws_iam_user" "audit" {
  name = "marche-securite-audit"
}
resource "aws_iam_user_policy" "audit" {
  name = "lecture-seule"
  user = aws_iam_user.audit.name
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # tout LIRE (configuration comprise : politiques, versionnage) — et rien d'autre : ce qui n'est pas
      # accordé est refusé
      { Effect = "Allow", Action = ["s3:Get*", "s3:List*", "iam:Get*", "iam:List*"], Resource = ["*"] },
    ]
  })
}
resource "aws_iam_access_key" "audit" {
  user = aws_iam_user.audit.name
}

output "audit" {
  description = "l'identité d'audit (lecture seule) : pour la surveillance de conformité"
  value       = { access_key = aws_iam_access_key.audit.id, secret_key = aws_iam_access_key.audit.secret }
  sensitive   = true
}
output "deploiement" {
  value     = { for c, k in aws_iam_access_key.deploiement : c => { access_key = k.id, secret_key = k.secret } }
  sensitive = true
}
