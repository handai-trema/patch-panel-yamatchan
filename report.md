#レポート課題 パッチパネルの機能拡張
> 授業で説明したパッチの追加と削除以外に，  
> 以下の機能をパッチパネルに追加してください．  

> 1. ポートのミラーリング  
> 2. パッチとポートのミラーリングの一覧  

> それぞれpatch_panelのサブコマンドとして実装してください．

# 課題に対するコメント
``Controller#send_flow_mod_modify``って無くなったんですか？  
ポートミラーリングの実装で，``Controller#send_flow_mod_modify``が使えないと，``Controller#send_flow_mod_delete``と``Controller#send_flow_mod_add``を併用しないといけないので不便でした．

## 実装
### ポートのミラーリング
以下のように，サブコマンド``mirror``に引数``detapath_id``，``モニターポート番号``，``ミラーポート番号``を指定すると，``monitor_port``で送受信されるパケットを``mirror_port``へコピーして転送されるようなフローエントリが登録されるコードを実装した．

```
$ bin/patch_panel mirror datapath_id monitor_port mirror_port
```

### パッチとポートのミラーリングの一覧
以下のように，サブコマンド``list``を実行すると，パッチは``* portA <-> portB``，ミラーは``+ portA --> portB``(portAをportBへミラー)といった形式で一覧が表示されるコードを実装した．

```
$ bin/patch_panel list
```

## 動作確認
ネットワーク構成を``patch_panel.conf``のように指定し，ポートミラーリングの動作確認を行った．  
なお，動作確認のシナリオとして，ポート1，ポート2間のパッチを生成し，ポート1をポート3へミラーリングすることを想定した．

```
【patch_panel.conf】
vswitch('patch_panel') { datapath_id 0xabc }

vhost ('host1') { ip '192.168.0.1' }
vhost ('host2') { ip '192.168.0.2' }
vhost ('host3') { ip '192.168.0.3' }

link 'patch_panel', 'host1'
link 'patch_panel', 'host2'
link 'patch_panel', 'host3'
```

## 実行結果
上述のシナリオに沿って実装したコードの動作確認を行った．  
その結果を以下に示す．
なお，適宜``# ＊＊＊＊``といった形式で実行結果に対するコメントを挿入している．(※``#dpid = 0xabc``はプログラムの標準出力でありコメントではない)

```
$ bin/trema run lib/patch_panel.rb -c patch_panel.conf -d

# パッチを生成
$ bin/patch_panel create 0xabc 1 2
$ bin/trema dump_flows patch_panel
NXST_FLOW reply (xid=0x4):
 cookie=0x0, duration=0.66s, table=0, n_packets=0, n_bytes=0, idle_age=0, priority=0,in_port=1 actions=output:2
 cookie=0x0, duration=0.622s, table=0, n_packets=0, n_bytes=0, idle_age=0, priority=0,in_port=2 actions=output:1

## host1 -> host2
$ bin/trema send_packet -s host1 -d host2
$ bin/trema show_stats host1
Packets sent:
  192.168.0.1 -> 192.168.0.2 = 1 packet
$ bin/trema show_stats host2
Packets recieved:
  192.168.0.1 -> 192.168.0.2 = 1 packet
$ bin/trema show_stats host3
# 当然ながらhost3にはパケットが届いていない

# パッチとポートミラーリングの一覧
$ bin/patch_panel list
#dpid = 0xabc
* 1 <-> 2 # 先ほど設定したパッチが表示されている

# ポートミラーリングの設定
$ bin/patch_panel mirror 0xabc 1 3
$ bin/trema dump_flows patch_panel
NXST_FLOW reply (xid=0x4):
 cookie=0x0, duration=4.339s, table=0, n_packets=1, n_bytes=42, idle_age=2, priority=0,in_port=1 actions=output:2,output:3
 cookie=0x0, duration=4.301s, table=0, n_packets=0, n_bytes=0, idle_age=4, priority=0,in_port=2 actions=output:1,output:3

## host1 -> host2
$ bin/trema send_packet -s host1 -d host2
$ bin/trema show_stats host1
Packets sent:
  192.168.0.1 -> 192.168.0.2 = 2 packets # host1 -> host2へパケットを送信
$ bin/trema show_stats host2
Packets recieved:
  192.168.0.1 -> 192.168.0.2 = 2 packets # host1 -> host2のパケットを受信
$ bin/trema show_stats host3
Packets recieved:
  192.168.0.1 -> 192.168.0.2 = 1 packet # host1 -> host2のパケットを受信 (ミラー)

## host2 -> host1
$ bin/trema send_packet -s host2 -d host1
$ bin/trema show_stats host1
Packets sent:
  192.168.0.1 -> 192.168.0.2 = 2 packets
Packets recieved:
  192.168.0.2 -> 192.168.0.1 = 1 packet # host2 -> host1のパケットを受信
$ bin/trema show_stats host2
Packets sent:
  192.168.0.2 -> 192.168.0.1 = 1 packet # host2 -> host1へパケットを送信
Packets recieved:
  192.168.0.1 -> 192.168.0.2 = 2 packets
$ bin/trema show_stats host3
Packets recieved:
  192.168.0.1 -> 192.168.0.2 = 1 packet
  192.168.0.2 -> 192.168.0.1 = 1 packet # host2 -> host1のパケットを受信 (ミラー)

# パッチとポートミラーリングの一覧
$ bin/patch_panel list
#dpid = 0xabc
* 1 <-> 2
+ 1 --> 3 (mirror)  # 新たにポートミラーリングが追加された
```

# 拡張課題
## ポートミラーリングの削除
暇だったらやる

```
$ bin/patch_panel del-mirror datapath_id monitor_port mirror_port
```

## パッチ追加時のエラーチェック
このままだと，以下のようなコマンドが通ってしまう(port1が二股)ので，
既にパッチが設定されているポートを指定した場合はエラーを出力するようにする．(暇だったらやる
)

```
$ bin/patch_panel create 0xabc 1 2
$ bin/patch_panel create 0xabc 1 3
```


