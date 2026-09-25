# 004_terraform_ansible_workshop.md レビュー結果（Ansible章）

本資料は `documents/workshop_materials/004_terraform_ansible_workshop.md`（Ansible実行・Playbook解説・トラブルシューティング・演習・まとめを含む章）を対象に、リポジトリの実ファイル（`ansible/run_script.yml`、`ansible/scripts/hostname.sh`、`terraform/terraform.tfvars`）および001〜003との整合性を検証したレビュー結果である。001〜003の指摘は既存の `documents/workshop_materials/review_001_003_terraform.md` を参照。

**追記（構成変更）**: レビュー後の作業でセッション外の変更により004が11〜19章のみとなり、20〜36章相当の内容が005に未修正のまま残っていたことが判明した。ユーザーの指示により、「20. TerraformとAnsibleを分けて考える」章は削除し、残りの内容は以下のように再配置した。
- Multipass自体の状態確認・VM一覧確認・VMログイン確認 → 002 5.3（トラブルシューティング）
- SSH接続確認 → 002 4.3（新設）
- Inventoryの接続情報確認・Ansible ping・切り分けフロー・早見表・演習問題 → 004 20〜23章（新設、本レビューの指摘を反映済み）
- 最終的な完成形・覚えてほしいポイント・まとめ → 005（全体のまとめとして再構成、24〜26章）

## 重要度高（実行すると失敗する／実ファイルと矛盾）【対応済み】

> 項目1〜6は004_terraform_ansible_workshop.mdに反映済み。項目2・8は実ファイル（`ansible/scripts/hostname.sh`、`terraform/terraform.tfvars`）に合わせる方針で修正した。

### 1. Playbookファイル名が実ファイルと不一致
- **該当**: 004 15.1「今回のファイルは `ansible/site.yml` とする」、16.2、17.1
- **問題点**: 一貫して`site.yml`と説明しているが、リポジトリの実ファイルは`ansible/run_script.yml`。`site.yml`は存在しない。
- **対応方針**: 本文中の`site.yml`という表記を実ファイル名`run_script.yml`に統一する。

### 2. Shellスクリプト名・内容が実ファイルと不一致
- **該当**: 004 15.2, 16, 17, 33, 35
- **問題点**: ドキュメントは`scripts/hello.sh`だが、実ファイルは`ansible/scripts/hostname.sh`。内容も異なる。ドキュメント版は`"Hello from Ansible!"` `"Hostname: ..."` `"Date: ..."`の3行、実ファイルは`"hostname: ..."` `"date: ..."`の2行（小文字・"Hello from"行なし）。
- **対応方針**: ファイル名・内容を実ファイルに合わせて修正するか、実ファイル側をドキュメントに合わせて更新するか方針を決める。

### 3. Playbookの相対パス指定がドキュメント内で自己矛盾し、かつ実装と異なる
- **該当**: 004 15.2（`cd ansible`済みの状態から`mkdir -p scripts`）、16.2（Playbook例の`cmd: ../scripts/hello.sh`）、16.4
- **問題点**: 15.2で`cd ansible`済みの状態から`mkdir -p scripts`しているため作成先は`ansible/scripts/`のはずだが、16.2のPlaybook例は`cmd: ../scripts/hello.sh`（`ansible/`から見て一段上の`../scripts/`を指す）になっており、自分で作成した`ansible/scripts/`ではなく存在しない`scripts/`（ansibleの外）を参照してしまう。16.4で「Ansible実行側から見たパス」と強調しているだけに致命的な誤り。実際の`run_script.yml`は`./scripts/hostname.sh`（`ansible/`直下のscripts）を参照しており、003の6.1ディレクトリ構成（`ansible/scripts/hostname.sh`）とも整合している。
- **対応方針**: Playbook例のパスを`scripts/hello.sh`（`..`なし）に修正する。

### 4. Playbookの内容が実ファイルと異なる
- **該当**: 004 16.2
- **問題点**: ドキュメント例は`hosts: servers` / `become: false` / `ansible.builtin.script: { cmd: ../scripts/hello.sh }`のみだが、実ファイル`run_script.yml`は`hosts: all` / `gather_facts: false` / `ansible.builtin.script: ./scripts/hostname.sh` に加えて`register: result`と`ansible.builtin.debug`タスクによる結果表示がある。`hosts`対象（`servers` vs `all`）、`gather_facts`の有無、`register`/`debug`による結果表示の有無など複数箇所が異なる。
- **対応方針**: Playbook例を実ファイルの内容に合わせる。

### 5. Inventoryのグループ名が003と矛盾
- **該当**: 004 13章、16.3、17.2
- **問題点**: 004は一貫して`[servers]`グループを使用しているが、003（7.5 inventory.ini.tpl、9.4 Inventory確認）で確定した実際の生成結果は`[ubuntu]`グループであり、`[servers]`というグループは存在しない。004の`hosts: servers`（16.3）は003の実際のinventoryと接続できない。
- **対応方針**: 004内の`[servers]`表記をすべて`[ubuntu]`に統一する。

### 6. Inventory例に接続必須の`[xxx:vars]`が欠落
- **該当**: 004 13.1
- **問題点**: Inventory例が`[servers]`グループとホスト行のみで、実際に必要な`ansible_user` / `ansible_ssh_private_key_file` / `ansible_python_interpreter`（003の`[ubuntu:vars]`セクション相当）が一切ない。この例のままでは秘密鍵もPythonインタプリタも指定されておらず、14章の`ansible ... -m ping`は実際には失敗する。
- **対応方針**: 003の`[ubuntu:vars]`と整合する形でInventory例に`[ubuntu:vars]`セクションを追加する。

## 重要度中【対応済み】

> 項目7〜9も反映済み。項目7は002の5.3を004の22・30章への参照に圧縮し、003の10章はTerraform固有の内容として維持した（004との重複箇所はない）。項目8はVM名を001〜004全体で`terraform.tfvars`の実際の値（`ubuntu1`/`ubuntu2`）に統一した。

### 7. トラブルシューティング内容が002/003と重複
- **該当**: 004 21〜32章、002 5.3、003 10章
- **問題点**: 004の21〜32章は「Multipassで問題が発生した場合の確認方法」を非常に詳しく扱っている（`multipass list`→`info`→`shell`→`cloud-init status`→SSH→Ansible pingという切り分け、早見表など）。これは002（5.3）・003（10章）に既に追加されているトラブルシューティング内容と重複している。
- **対応方針**: 「Multipass単体の切り分け」は004の21〜32章に一本化し、002の5.3・003の10章は簡易な参照リンクに留めるなど、章をまたいだ再整理を検討する。

### 8. VM名の表記がterraform.tfvarsと不一致（001〜004共通）
- **該当**: 004全般（特に35章 演習1）
- **問題点**: 004は一貫して`ansible-vm-1` / `ansible-vm-2`という名前を使っているが、実際の`terraform/terraform.tfvars`では`ubuntu1` / `ubuntu2`という名前になっている。001〜003にも共通する問題（前回スコープ外として保留）だが、004でも同様に踏襲されており、演習1（VMを3台構成にする）などVM名を直接扱う箇所で読者が混乱する。
- **対応方針**: 001〜004全体でVM名表記をterraform.tfvarsの実際の値（`ubuntu1`/`ubuntu2`等）に統一するか、tfvars.example側をドキュメントに合わせて`ansible-vm-1`/`ansible-vm-2`に変更するか方針を決める。

### 9. `ping`モジュールの参照方法が章内で不統一
- **該当**: 004 14章（`-m ping`）、27章（`-m ansible.builtin.ping`）
- **問題点**: 同じ操作を短縮名とFQCN（完全修飾コレクション名）で異なる書き方で説明している。誤りではないが不統一。
- **対応方針**: どちらかの書き方に統一する（FQCN推奨）。

## 重要度低【対応済み】

> 項目10も反映済み。

### 11.（追加指摘）25章のSSH接続例が実際のcloud-init設定と不一致
- **該当**: 004 25章（SSH接続を確認）
- **問題点**: `ssh ubuntu@<VMのIPアドレス>`となっていたが、cloud-init（003 8.2）で作成される接続用ユーザーは`ubuntu`ではなく`ansible`であり、また秘密鍵（4.2で作成した`~/.ssh/ansible/id_ed25519`）を明示しないとデフォルト鍵で接続を試みてしまう。
- **対応方針**: `ssh -i ~/.ssh/ansible/id_ed25519 ansible@<VMのIPアドレス>`に修正した。31章の切り分けフロー図中の`ssh ubuntu@IP`は概念図の略記のため未変更。

### 10. ansible.cfgへの言及がない【対応済み】
- **該当**: 004 14, 17, 27章（`ansible-playbook`/`ansible`コマンド実行例）
- **問題点**: リポジトリには`ansible.cfg`が存在せず、`ansible_ssh_private_key_file`をinventory側でしか指定していない。SSH初回接続時のホスト鍵確認プロンプト（`StrictHostKeyChecking`）について触れていないため、ワークショップ中に想定外のプロンプトが出る可能性がある。
- **対応方針**: `ansible.cfg`は導入せず、代わりにTerraform側でSSHホスト鍵をPinningする方式を採った（`documents/ssh-host-key-pinning-design.md`）。`multipass_file_download`でVMのSSHホスト公開鍵をmultipassd経由（SSHを介さない）で取得し、`ansible/known_hosts`を生成、Inventoryの`[ubuntu:vars]`に`ansible_ssh_common_args`（`StrictHostKeyChecking=yes` + `UserKnownHostsFile`）を追加した。これにより初回接続時の`yes/no`プロンプト自体が発生しなくなるため、プロンプトへの対処ではなく発生条件そのものを取り除いている。004 12.4・13章に反映済み。
