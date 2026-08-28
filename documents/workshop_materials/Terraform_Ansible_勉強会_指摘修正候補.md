# Terraform・Ansible勉強会資料 指摘・修正候補

## 1. 全体評価

| 評価項目 | 現状 | 改善後の目標 | コメント |
|---|---:|---:|---|
| 構成 | 86点 | 93点 | 大枠は良い。Terraform → cloud-init → Ansibleの順序も自然 |
| 技術的正確性 | 82点 | 92点 | いくつか一般化・断定表現を修正したい |
| 分かりやすさ | 84点 | 94点 | 用語導入と「なぜこのツールを使うのか」を補強したい |
| 図解 | 88点 | 94点 | 図は充実。似た図の役割を整理するとさらによい |
| 演習・定着 | 72点 | 92点 | 「自分で設計する」「再実行する」演習を追加したい |
| **総合** | **82点** | **93点程度** | 土台は十分強い。概念のつながりと演習を補強すると完成度が上がる |

---

# 2. 最優先で追加・修正したい項目

## 2.1 「今回作るもの」を冒頭に追加

最初に、勉強会で最終的に何を作るのかを1枚で示す。

```text
Mac
 │
 ├─ Terraform
 │      ↓
 │   Multipass
 │      ↓
 │   Ubuntu VM × 2
 │
 └─ Ansible
        ↓ SSH
     Ubuntu VM × 2
        ↓
   Shellスクリプト実行
```

### 狙い

各技術を個別に覚えるのではなく、

> 「VMを作って、そのVMに対して自動化を行う」

という一つのストーリーとして理解させる。

---

## 2.2 「用語一覧」を序盤に追加

若手向けであれば、最初に以下を提示するとよい。

| 用語 | この勉強会での意味 |
|---|---|
| VM | Mac上で動かすUbuntuの仮想マシン |
| Multipass | Ubuntu VMを作成・管理するツール |
| Terraform | インフラをコードで管理するツール |
| Provider | Terraformと外部サービスをつなぐプラグイン |
| cloud-init | VM初回起動時の初期設定を行う仕組み |
| SSH | MacからVMへ接続する仕組み |
| Ansible | VMの設定・操作を自動化するツール |
| Controller | Ansibleを実行する側 |
| Managed Node | Ansibleから操作される側 |
| Inventory | Ansibleの操作対象一覧 |
| Playbook | Ansibleの処理手順 |
| Module | Ansibleが実際に処理を行う機能 |
| Idempotency | 何度実行しても目的の状態に収束する性質 |

---

# 3. Terraform周辺の修正候補

## 3.1 Terraform / cloud-init / Ansibleの役割説明

### 現状の問題

「Terraform = 外枠」「cloud-init / Ansible = 中身」という説明は分かりやすいが、

> 実務ではこれがベストプラクティス

と断定すると強すぎる。

### 推奨表現

```text
Terraform
  ↓
「VMという箱を作る」

cloud-init
  ↓
「VM初回起動時に最低限の準備をする」

Ansible
  ↓
「VMの中の設定・操作を自動化する」
```

さらに、

> Terraform、cloud-init、Ansibleの責務を分ける構成は、今回のような検証環境で理解しやすい設計パターンの一つである。

程度にする。

---

## 3.2 Terraform Providerの説明を追加

初心者は、

> TerraformがMultipassを直接操作している

と誤解しやすい。

以下を追加する。

```text
Terraform
   │
   │ Provider
   ▼
Multipass
   │
   ▼
Ubuntu VM
```

説明：

> Terraform本体がすべてのサービスを直接操作するわけではない。Providerと呼ばれるプラグインを介して、各種サービスや製品を操作する。

---

## 3.3 terraform init / plan / apply / destroy

それぞれの意味を一言で整理する。

| コマンド | 意味 |
|---|---|
| `terraform init` | Terraformを実行できる状態に初期化する |
| `terraform plan` | どのような変更が行われるか確認する |
| `terraform apply` | 実際に変更を適用する |
| `terraform destroy` | Terraform管理下のリソースを削除する |

特に `plan` について、

> 「いきなり変更せず、まず差分を確認する」

という安全確認の意味を強調する。

---

## 3.4 Terraform Stateを独立して説明

`terraform.tfstate` は今回の教材でも重要なので、独立した説明を追加する。

```text
              Terraform
                  │
        ┌─────────┴─────────┐
        ▼                   ▼
   configuration          state
      (*.tf)           terraform.tfstate
        │                   │
        └─────────┬─────────┘
                  ▼
            現在の状態との差分
```

説明：

> Terraformは設定ファイルだけでなくstateを利用して、Terraformが管理しているリソースの状態を把握する。

---

## 3.5 variables.tf / terraform.tfvars / main.tf

3つの関係を図示する。

```text
variables.tf
「どんな変数を受け取るか」
        │
        ▼
terraform.tfvars
「実際にどんな値を設定するか」
        │
        ▼
main.tf
「変数をどう使うか」
```

例：

```hcl
# variables.tf
variable "vm_image" {
  type = string
}
```

```hcl
# terraform.tfvars
vm_image = "24.04"
```

```hcl
# main.tf
image = var.vm_image
```

---

## 3.6 terraform.tfvarsの説明を修正

### 修正前の考え方

> terraform.tfvarsはバージョン管理しない。

### 推奨

> `terraform.tfvars` に個人環境依存の情報や秘密情報が含まれる場合は、Git管理から除外する。

教材では、

```text
terraform.tfvars
terraform.tfvars.example
```

の2つを用意すると実務的。

---

## 3.7 for_eachの説明を強化

例えば、

```hcl
resource "multipass_instance" "node" {
  for_each = var.nodes
}
```

について、

```text
nodes

ubuntu1 ──→ multipass_instance.node["ubuntu1"]
ubuntu2 ──→ multipass_instance.node["ubuntu2"]
```

と図示する。

| 式 | 内容 |
|---|---|
| `each.key` | `ubuntu1`などのVM名 |
| `each.value` | CPU、メモリ、ディスクなどの設定 |

---

# 4. SSH / cloud-init周辺の修正候補

## 4.1 SSHを全体の橋渡し役として説明

今回の構成ではSSHが重要。

```text
Terraform
  │
  │ Multipass Provider
  ▼
VMを作成

cloud-init
  │
  ▼
SSH接続に必要な初期設定

Ansible
  │
  │ SSH
  ▼
VMを操作
```

これにより、

> TerraformがVMを作る  
> AnsibleがSSHでVMを操作する

という責務の違いを明確にできる。

---

## 4.2 SSH鍵の説明

```text
Mac
├── id_ed25519       ← 秘密鍵
│
└── id_ed25519.pub   ───────→ VM
                              ~/.ssh/authorized_keys
```

説明：

> 秘密鍵はMac側で保持し、公開鍵をVM側に登録する。Ansibleは秘密鍵を使ってSSH接続する。

---

## 4.3 cloud-initの「なぜ」を追加

単なる定義だけでなく、

```text
VM作成
 ↓
cloud-init
 ↓
ユーザー作成
 ↓
SSH公開鍵登録
 ↓
Pythonなど必要な環境を準備
 ↓
Ansibleから接続可能
```

という流れを示す。

重要なメッセージ：

> cloud-initは、Ansibleを実行するための最低限の土台をVM作成時に準備するために利用する。

---

# 5. Ansible周辺の修正候補

## 5.1 Controller / Managed Nodeを正式に説明

```text
             Ansible Controller
                    │
                  SSH
          ┌─────────┴─────────┐
          ▼                   ▼
     Managed Node         Managed Node
       ubuntu1              ubuntu2
```

| 用語 | 今回 |
|---|---|
| Ansible Controller | Mac |
| Managed Node | ubuntu1 / ubuntu2 |
| Connection | SSH |
| Inventory | Managed Nodeの一覧 |
| Playbook | 実行する処理 |
| Module | 実際の処理 |

---

## 5.2 Inventory / Playbook / Module / Variables

4つの役割として整理するとよい。

```text
Inventory
   ↓
どこに？

Playbook
   ↓
何を？

Module
   ↓
どうやって？

Variables
   ↓
どんな値で？
```

---

## 5.3 ansible.builtin.ping

現在の説明を維持しつつ、

> `ping` moduleはICMP pingではなく、「Ansibleから対象ホストを操作できるか」を確認するためのmodule

と強調する。

---

# 6. Shell / scriptの説明で注意したい点

## 6.1 「MacのShellをリモート実行」という表現を修正

誤解を避けるため、

> Mac上にあるShellスクリプトをAnsibleによってVMへ転送し、対象VM上で実行する。

とする。

実行イメージ：

```text
Mac
 │
 │ script module
 ▼
Shellスクリプトを転送
 │
 ▼
VM上で実行
```

つまり、**スクリプトのファイルがMacにあることと、スクリプトの実行場所がMacであることは別**である。

---

## 6.2 Ansible = Shell実行ツールにならないようにする

以下のメッセージを追加する。

> AnsibleはSSHでコマンドを投げるだけのツールではない。

```text
Ansible

「サーバーをこの状態にしたい」
        ↓
適切なModuleを利用
        ↓
対象サーバーを目的の状態へ
```

`script`、`command`、`shell`だけでなく、`apt`、`copy`、`template`、`service`なども紹介するとよい。

---

# 7. 冪等性を「説明」だけでなく「体験」させる

これは最優先で追加したい演習。

例：

```yaml
- name: Install nginx
  ansible.builtin.apt:
    name: nginx
    state: present
```

1回目：

```text
changed=1
```

2回目：

```text
changed=0
```

ここで、

> 「何度実行しても、必要な変更だけを行って目的の状態に収束する」

というAnsibleの重要な特徴を体験させる。

---

# 8. トラブルシューティングの構成

現在のレイヤーによる切り分けは良いので、そのまま活かす。

```text
Multipass
   ↓
VM
   ↓
SSH
   ↓
Ansible ping
   ↓
Playbook
   ↓
Module
```

基本原則：

> 上位の処理を調べる前に、下位の層が正常か確認する。

例えば、

```text
Playbookが失敗
    ↓
まずAnsible ping
    ↓
失敗？
    ↓
SSH / Inventoryを確認
```

という切り分け手順を示す。

---

# 9. 失敗させる演習を追加

初学者には、成功例だけでなく意図的な失敗が有効。

## 失敗1：SSH鍵を間違える

```text
Permission denied (publickey)
```

→ SSHの問題

## 失敗2：InventoryのIPを間違える

```text
UNREACHABLE
```

→ Inventory / SSHの問題

## 失敗3：Playbookのhostsを間違える

```yaml
hosts: server
```

→ 対象ホスト指定の問題

## 失敗4：存在しない変数を使う

```jinja2
{{ role }}
```

→ `role is undefined`

失敗 → 原因特定 → 修正 → 再実行、という流れを体験させる。

---

# 10. 演習をLevel 1～3に分ける

## Level 1：既存処理を変更

```text
Shellスクリプトを変更
↓
Ansible実行
↓
結果確認
```

## Level 2：対象を変更

Inventoryのグループを変更し、

```yaml
hosts: server1
```

など対象ホストを変えて実行する。

## Level 3：自分で自動化

課題例：

> `/tmp/workshop.txt`を2台のVMに作成せよ。

条件：

- Playbookを自分で作成
- `copy` moduleを使用
- 2台とも同じ内容
- 2回実行して2回目が`changed=0`

---

# 11. 最終自由課題を追加

勉強会のゴールに直結する課題。

### 課題例

- VMを3台に変更する
- 各VMにhostnameを記録したファイルを作成する
- nginxをインストールして起動する
- `template` moduleでVMごとに異なる設定ファイルを生成する

最後に、

```text
terraform destroy
↓
terraform apply
↓
Ansible実行
↓
同じ結果になる
```

まで確認させる。

---

# 12. 最後に「自動化検証の基本パターン」を追加

今回の勉強会のゴールそのものになるページ。

```text
① 何を検証したい？
       ↓
② VMを作る
       ↓
③ 初期設定する
       ↓
④ SSH接続を確認
       ↓
⑤ Inventoryに登録
       ↓
⑥ ansible ping
       ↓
⑦ Playbookを作る
       ↓
⑧ Moduleを選ぶ
       ↓
⑨ 実行する
       ↓
⑩ 再実行して冪等性を確認
       ↓
⑪ destroy
       ↓
⑫ 必要なら再構築
```

この「型」を持ち帰ってもらうことを、勉強会の最終目標として明示する。

---

# 13. 図解の整理

現在の資料は図が充実しているため、図を増やしすぎるより、役割を整理する。

## 図A：全体構成

```text
Mac
├── Terraform
├── Ansible
└── Multipass
      ├── VM1
      └── VM2
```

## 図B：構築フロー

```text
Terraform
 ↓
Multipass
 ↓
VM
 ↓
cloud-init
 ↓
SSH可能
```

## 図C：Ansible実行フロー

```text
Inventory
 ↓
Playbook
 ↓
Module
 ↓
SSH
 ↓
VM
```

## 図D：トラブルシューティング

```text
Multipass
 ↓
VM
 ↓
SSH
 ↓
Ansible ping
 ↓
Playbook
```

既存図と役割が重複するものは、この4種類に整理する。

---

# 14. 修正優先順位

時間が限られる場合は以下の順番がおすすめ。

| 優先度 | 対応 | 理由 |
|---|---|---|
| ★★★★★ | 自動化検証の基本パターン追加 | 勉強会のゴールに直結 |
| ★★★★★ | 冪等性の実演追加 | Ansibleの本質を体験できる |
| ★★★★★ | SSHの役割を明確化 | Terraform / cloud-init / Ansibleの関係が理解しやすくなる |
| ★★★★★ | 今回作るものを冒頭に追加 | 全体像を最初から持たせられる |
| ★★★★☆ | Controller / Managed Node追加 | Ansibleの基本概念として重要 |
| ★★★★☆ | Terraform State追加 | Terraform理解に重要 |
| ★★★★☆ | Provider追加 | Terraformの仕組みを理解できる |
| ★★★☆☆ | 用語一覧追加 | 初学者の認知負荷を下げられる |
| ★★★☆☆ | 失敗演習追加 | トラブルシューティング能力を育てられる |
| ★★☆☆☆ | 図の整理 | 現状でも十分充実している |

---

# 15. 講師目線での最終方針

資料を大幅に作り直す必要はない。

改善の軸は、

```text
知識を教える
    ↓
仕組みを理解する
    ↓
実際に動かす
    ↓
わざと変更する
    ↓
失敗させる
    ↓
原因を切り分ける
    ↓
自分で自動化する
```

にすること。

特に、

> Terraform = VMを用意する  
> cloud-init = Ansibleを使える土台を作る  
> SSH = MacとVMをつなぐ  
> Ansible = VMを自動化する

という4つの関係を最後まで一貫して意識させると、若手でも理解しやすい教材になる。

最終的には、受講者が

> 「TerraformとAnsibleの使い方を知っている」

ではなく、

> **「検証したいことがあれば、自分でVMを用意し、Ansibleで自動化して検証できる」**

状態になることを評価基準にするとよい。
