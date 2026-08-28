# 001〜003 レビュー結果（Terraform構築範囲）

本資料は、`documents/workshop_materials/001_terraform_ansible_workshop.md` 〜 `003_terraform_ansible_workshop.md`（勉強会の目的・事前準備・Terraformを用いたVM構築までの範囲）を対象としたレビュー結果をまとめたものであり、Ansible章（004・005）は対象外とする。

---

## 重要度高（内容の欠落・矛盾）【対応済み】

> 以下の4件は003_terraform_ansible_workshop.mdに反映済み（実際の`terraform/variables.tf`・`terraform/terraform.tfvars.example`・`terraform/inventory.ini.tpl`・`ansible/`配下の内容に基づく）。

### 1. 003 - variables.tf / terraform.tfvars が一切登場しない

- **該当ファイル・章番号**: 003 6.1（ディレクトリ構成）、7.2（main.tf）
- **問題点**: ディレクトリ構成（6.1）に `terraform/terraform.tfvars` と `terraform/variables.tf` が明記され、main.tf（7.2）は `var.nodes` / `var.vm_image` / `var.ssh_public_key_path` / `var.ssh_private_key_path` / `var.ansible_inventory_path` を多数参照しているが、それらの定義内容・設定例が本文に一度も出てこない。読者が実際に値を何に設定すればよいか分からない。
- **対応方針**: 7章か9章に `variables.tf` の定義と `terraform.tfvars` の記入例を追加する。

### 2. 003 - inventory.ini.tpl の中身が示されない

- **該当ファイル・章番号**: 003 7.2（main.tf）、9.6（Inventory確認）
- **問題点**: main.tf の `local_file.ansible_inventory` が `inventory.ini.tpl` をテンプレートとして使い、`ssh_private_key_path` を変数として渡しているが、テンプレート自体の内容が本文にない。9.6で表示される生成結果例には `ansible_ssh_private_key_file` 相当の記述がなく、`ssh_private_key_path` が実際どう使われているのか読者には確認できない。
- **対応方針**: テンプレートファイルの中身を8章か9章に追加し、整合性を取る。

### 3. 003 - 8.2の「YOUR_SSH_PUBLIC_KEYを置き換える」説明が実装と矛盾

- **該当ファイル・章番号**: 003 7.2（main.tf）、8.2（cloud-init.yaml）
- **問題点**: main.tf（7.2）はすでに `templatefile()` と `local.ssh_public_key` で公開鍵を自動注入する設計になっている。にもかかわらず8.2では「`YOUR_SSH_PUBLIC_KEY` を手動でMacの公開鍵に置き換える」という、手動運用を前提にした古い説明が残っている。
- **対応方針**: 自動化されたフローと矛盾するため該当説明を削除、または「テンプレート変数として自動的に埋め込まれる」旨に修正する。

### 4. 003 - ディレクトリ構成とロール表のファイル名不一致

- **該当ファイル・章番号**: 003 6.1（ディレクトリ構成／ファイル役割表）
- **問題点**: 6.1のディレクトリツリーは `ansible/run_script.yml` と `ansible/scripts/hostname.sh` だが、直後のロール表では `ansible/site.yml` と `scripts/hello.sh` になっている。004以降で正式名称が決まるとしても、003単体を読んだ時点で名前が食い違っているのは混乱の元。
- **対応方針**: どちらかの名称に統一する。

---

## 重要度中【対応済み】

> 以下の4件は002・003に反映済み。項目5はMultipass自体の問題を002「5.3 トラブルシューティング」に、terraform apply固有の問題を003「10. トラブルシューティング」に分けて対応（1.2の目標リストは維持）。

### 5. 001 - 学習目標「Multipassで問題が発生した場合の確認方法」が001〜003内で未消化

- **該当ファイル・章番号**: 001 1.2（この勉強会で理解すること）
- **問題点**: 1.2の目標リストに含まれているが、Ansibleの章ではなくMultipass/Terraformの範囲の話のはずであり、004以降（Ansible章）に先送りするのは筋が違う。
- **対応方針**: 003の終わり（VM構築の実行後）あたりにトラブルシューティング節（`multipass list` が失敗する、`terraform apply` がタイムアウトする等）を追加するか、目標リストから該当項目を一旦外す調整を行う。

### 6. 002 - Terraformインストールリンクが誤り

- **該当ファイル・章番号**: 002 4.1.2（Terraform - インストール）
- **問題点**: `[Install Terraform](/aws-get-started/install-cli)` はAWS CLIのインストールパスがそのまま残っており、Terraformの公式インストール手順にリンクしていない。
- **対応方針**: `https://developer.hashicorp.com/terraform/install` 等に修正する。

### 7. 002 - SSH鍵の確認コマンドのパスが鍵作成先と不一致

- **該当ファイル・章番号**: 002 4.2（SSH鍵の準備）
- **問題点**: 鍵は `~/.ssh/ansible/id_ed25519` に作成しているのに、公開鍵確認コマンドは `cat ~/.ssh/id_ed25519.pub`（`ansible/` が抜けている）になっている。実行するとファイルが見つからずエラーになる。
- **対応方針**: `cat ~/.ssh/ansible/id_ed25519.pub` に修正する。

### 8. 003 - terraform destroy（後片付け）の手順が本文にない

- **該当ファイル・章番号**: 003 7.1（Terraformの役割）、9章（VM構築の実行）
- **問題点**: 7.1の図では `terraform apply` → 運用 → 廃止時に `terraform destroy` という流れが示されているが、9章の実行手順は `apply` までで終わっており、`destroy` での後片付けが説明されていない。
- **対応方針**: ワークショップ終了時にVMを削除する手順として9章末に追加する。

---

## 重要度低（軽微・体裁）【対応済み】

> 項目9は対応済み（002 4.1.3の見出しレベルは`#### インストール`等に統一済み）。項目10・11も002に反映済み。

### 9. 002 4.1.3 - 見出しレベルの不揃い

- **該当ファイル・章番号**: 002 4.1.3（Ansible）
- **問題点**: 4.1.1/4.1.2は `#### インストール` の見出しレベルだが、4.1.3のみ `### Ansibleとは` / `### インストール` と1段浅い。
- **対応方針**: 他の項と揃うよう見出しレベルを修正する。

### 10. 002 - 各ツールのインストール後の動作確認ステップがない

- **該当ファイル・章番号**: 002 4.1（必要なソフトウェア）
- **問題点**: 各ツールをインストールした後、`multipass version` / `terraform version` / `ansible --version` などで導入確認するステップが無い。
- **対応方針**: 事前準備の章に簡単な動作確認ステップを追加し、後続作業でのトラブルを減らす。

### 11. 002 セクション5「Multipass概要」- 4.1.1との役割分担が目次上不明瞭

- **該当ファイル・章番号**: 002 4.1.1（Multipass）、5章（Multipass概要）
- **問題点**: すでに4.1.1でMultipassを紹介済みで、5章は基本コマンド一覧を後出しする構成になっている。内容自体に問題はないが、「インストール紹介（4.1.1）」と「操作コマンド解説（5章）」の役割分担が目次上で分かりにくい。
- **対応方針**: 目次または章タイトルで両者の役割分担を明示する。
