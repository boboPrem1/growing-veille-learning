# Le stockage objet du VPC Europe, déclaré : ce que stockage.sh faisait à la main au Palier 1.

resource "aws_s3_bucket" "statique" {
  provider = aws.stockage
  bucket   = "marche-statique"
}
resource "aws_s3_bucket_policy" "statique" {
  provider = aws.stockage
  bucket   = aws_s3_bucket.statique.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid    = "LecturePublique", Effect = "Allow", Principal = "*"
      Action = ["s3:GetObject"], Resource = ["${aws_s3_bucket.statique.arn}/*"]
    }]
  })
}
resource "aws_s3_bucket" "factures" {
  provider = aws.stockage
  bucket   = "marche-factures"
}
resource "aws_s3_bucket_versioning" "factures" { # une facture écrasée ou supprimée se récupère
  provider = aws.stockage
  bucket   = aws_s3_bucket.factures.id
  versioning_configuration { status = "Enabled" }
}

# ------------------------------------------------------------------ identités (moindre privilège)
resource "aws_iam_user" "app" {
  provider = aws.stockage
  name     = "marche-app"
}
resource "aws_iam_user_policy" "app" {
  provider = aws.stockage
  name     = "factures"
  user     = aws_iam_user.app.name
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [{ Effect = "Allow", Action = ["s3:PutObject", "s3:GetObject"], Resource = ["${aws_s3_bucket.factures.arn}/*"] }]
  })
}
resource "aws_iam_access_key" "app" { # rangée dans OpenBao (secrets.tf), jamais dans un fichier
  provider = aws.stockage
  user     = aws_iam_user.app.name
}

# ------------------------------------------------------------------ les ressources statiques du site
resource "random_bytes" "catalogue" { # une « grosse » image de 400 Ko
  length = 400000
}
locals {
  objets = {
    "app.v1.css" = { contenu = "body { font-family: sans-serif; color: #1d3557; }\n", type = "text/css" }
    "logo.svg"   = { contenu = "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"120\" height=\"40\"><text x=\"4\" y=\"28\" font-size=\"24\">Marché</text></svg>\n", type = "image/svg+xml" }
  }
}
resource "aws_s3_object" "statique" {
  provider      = aws.stockage
  for_each      = local.objets
  bucket        = aws_s3_bucket.statique.id
  key           = each.key
  content       = each.value.contenu
  content_type  = each.value.type
  cache_control = "public, max-age=86400" # noms versionnés + cache long : pas d'invalidation
}
resource "aws_s3_object" "catalogue" {
  provider       = aws.stockage
  bucket         = aws_s3_bucket.statique.id
  key            = "catalogue.jpg"
  content_base64 = random_bytes.catalogue.base64
  content_type   = "image/jpeg"
  cache_control  = "public, max-age=86400"
}
