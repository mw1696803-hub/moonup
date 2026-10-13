# MoonUp Rete 鍙鐜版紨绀鸿鏄?
鏈枃浠舵彁渚涗竴閿鐜版楠や笌鐪熷疄杩愯杈撳嚭蹇収锛?026-10-01 鍦?MoonBit 宸ュ叿閾?`moon 0.1.20260920` 涓嬪疄娴嬶級锛屽搴旇禌浜嬮獙鏀舵爣鍑?03銆岃兘澶熻繍琛屻€嶃€?
## 涓€閿鐜?
```bash
git clone https://github.com/mw1696803-hub/moonup.git
cd moonup
moon install        # 鎷夊彇渚濊禆锛堜粎 MoonBit core锛屾棤绗笁鏂逛緷璧栵級
moon test           # 91 涓崟鍏冩祴璇曪紙鍚?lib/rete 鐨?15 涓?Rete 缃戠粶娴嬭瘯锛?moon run main       # 绔埌绔?Demo锛氳法浜嬪疄椋庢帶 / 宸ュ崟璺敱锛堝叡浜?alpha锛? 搴撳瓨杩為攣 / OR路NOT 澶嶅悎鏉′欢 + 鍙€夌粍浠?moon build --release --target wasm-gc   # 鏋勫缓娴忚鍣?WASM锛坉ocs/moonup.wasm锛?```

## 杩愯瑕佹眰

- MoonBit 宸ュ叿閾撅紙`moon` 鍛戒护锛夛紝瀹夎瑙?<https://www.moonbitlang.com/download/>
- 绾?MoonBit core 瀹炵幇锛屾棤浠讳綍绗笁鏂逛緷璧?- 缃戦〉婕旂ず闇€ HTTP 鏈嶅姟鎵撳紑 `docs/moonup-demo.html`锛坒ile:// 鏃犳硶鍔犺浇 WASM锛?
## 鐪熷疄杈撳嚭蹇収

### 1. moon test

```
Total tests: 93, passed: 91, failed: 0.
```

### 2. moon run main锛堢湡瀹?stdout锛屾湭鍒犳敼锛?
```text
锘?== MoonUp Rete: MoonBit 浜х敓寮忚鍒欏紩鎿庯紙Rete 缃戠粶锛?==

[0A] 瀹炴椂椋庢帶锛氳法浜嬪疄鍏宠仈锛坥rder 脳 customer 脳 device锛?    瑙勫垯锛氬ぇ棰濊鍗?&& 鏂板鎴?&& 璁惧楂橀闄?鈫?浜哄伐澶嶆牳
    alpha鑺傜偣=5 beta鑺傜偣=6 terminal=2
    瑙﹀彂 5 鏉? risk_hold, risk_hold, risk_attach, risk_hold, risk_attach
    璁㈠崟鏈€缁堢姸鎬? status=hold tags=risk_device
    瀹㈡埛鏍囩: high_risk
    鈫?鍚屼竴寮曟搸鎵胯浇璺ㄤ簨瀹炲叧鑱旓紱new_customer/澶ч/楂橀闄╁垎寮€鏄笁鏉¤鍒欎篃鍚勮嚜鎴愮珛

[0B] 宸ュ崟璺敱锛氬叡浜瓙鏉′欢锛圴IP 鏉′欢鍙紪璇戜竴娆★級
    涓ゆ潯瑙勫垯鍏变韩 customer.vip==true锛孯ete 鍏变韩璇?alpha 鑺傜偣
    鍏变韩鍓嶆潯浠舵暟=2 鏉¤鍒?鈫?alpha鑺傜偣=2锛圴IP 鏉′欢 1 涓叡浜妭鐐癸紝鏈噸澶嶇紪璇戯級
    瑙﹀彂 5 鏉? vip_senior, vip_senior, vip_sla, vip_senior, vip_sla

[0C] 搴撳瓨淇冮攢锛氳繛閿佹縺娲伙紙涓嬪崟鈫掓墸搴撳瓨鈫掕ˉ璐р啋鍐嶈Е鍙戯級
    瑙﹀彂閾? stock_apply, stock_reorder
    瑙﹀彂杞ㄨ抗锛堝墠 3 鏉★級:
      rule=stock_apply facts=[2,1,2] action=product.stock-=order.qty & order.status=fulfilled
      rule=stock_reorder facts=[3] action=product.stock+=100 & action=reorder_triggered
    鈫?鍔ㄤ綔淇敼浜嬪疄浼氳Е鍙戝閲忎紶鎾笌杩為攣婵€娲伙紝fire limit 闃叉鏃犻檺寰幆

[0D] 澶嶅悎鏉′欢锛歄R 缁?|| 涓庡惁瀹?!锛圖SL 澧炲己锛?    瑙勫垯1 (OR) : (customer.level==VIP && ticket.type==refund) || order.amount>100000
    瑙勫垯2 (NOT): order.status==placed && !customer.blacklist==true
    VIP+閫€娆惧伐鍗?鈫?瑙﹀彂: or_rule
    15 涓囪鍗曪紙鏃?VIP锛夆啋 瑙﹀彂: or_rule
    placed 璁㈠崟锛堟棤瀹㈡埛锛夆啋 瑙﹀彂: not_rule
    placed 璁㈠崟 + 榛戝悕鍗曞鎴?鈫?瑙﹀彂: 锛圢OT 鎷︽埅锛?    鈫?|| 缁勪笌 ! 鍚﹀畾鍦ㄥ悓涓€寮曟搸缂栬瘧鎵ц锛氳鍒欏嵆鏁版嵁锛屽鍚堟潯浠舵棤闇€鏀瑰紩鎿?
[1] Evidence 璇佹嵁鍒嗙骇锛堝彲閫夌粍浠讹紝涓庡紩鎿庤В鑰︼級
  缃俊搴? High | 璇佹嵁 4 鏉★紝鏁翠綋缃俊搴﹂珮锛涘瓨鍦ㄩ珮鏉冮噸璇佹嵁锛堜功闈?璧勬簮/缁撴灉/閲嶅琛屼负锛夛紝缁撹鍙潬
  缂哄け淇℃伅: SLA 杩濈害璁ゅ畾鏍囧噯, 瀹℃壒璐熻矗浜?  鈫?浠讳綍闇€瑕佽瘉鎹垎绾х殑鍐崇瓥杩囩▼閮藉彲澶嶇敤锛堥鎺т妇璇併€佸鏍告潗鏂欍€佺哗鏁堣瘎浼扮瓑锛?
[2] Guardrail 鍐崇瓥鍋忚鎶ゆ爮锛堝彲閫夌粍浠讹紝涓庡紩鎿庤В鑰︼級
  鏄惁瀹夊叏閫氳繃: false
    鈿?杞堪鏀惧ぇ鐥涜嫤锛氳浆杩板彲鑳芥斁澶х棝鑻︽椂鍒伙紝鍥炲埌璇佹嵁娓呭崟
    鈿?鎺緸涓庤涓虹煕鐩撅細鎺緸婕備寒浣嗚涓虹煕鐩撅紝浠ラ噸澶嶈涓轰负鍑?    鈿?甯屾湜鎵洸鍒ゆ柇锛氭€ラ渶璁ゅ彲鏄撹繃搴︿俊浠绘壙璇猴紝鍏堥獙璇?    鈿?杩囧害鍏辨儏鍙欒堪鑰咃細鍗曟柟鍙欒堪+鎯呯华娴擄紝淇濇寔涓珛
  蹇呮煡椤?
    路 浠€涔堣瘉鎹敮鎸佽繖涓В璇伙紵
    路 浠€涔堣瘉鎹弽瀵瑰畠锛?    路 浠€涔堜細鏀瑰彉缁撹锛?    路 鏈夋病鏈夋洿瀹夊叏鐨勫皬娴嬭瘯锛?    路 鐢ㄦ埛褰撳墠鐘舵€佽兘鍚︽墽琛岃繖鏉″缓璁紵
  鈫?闃茬殑鏄喅绛栧亸瑙佹湰韬紙杞堪鏀惧ぇ/鎺緸鐭涚浘/浠呭嚟鎰熻锛夛紝涓嶇粦瀹氫换浣曚笟鍔″満鏅?
[3] Case 妗堜緥搴擄紙鍙€夌粍浠讹紝涓庡紩鎿庤В鑰︼級
  鍛戒腑 2 鏉″唴缃ず渚嬫渚嬶紙婕旂ず鏁版嵁锛屾満鍒跺彲鎺ヤ换鎰忛鍩燂級
    路 c-promotion [鍙ｅご鎵胯杞负涔﹂潰鏉′欢锛屾寜鏃堕棿绾块獙璇佸厬鐜癩
    路 c-multi-leader [澶氶瀵煎啿绐佸厛瀵归綈鍐嶆墽琛岋細璁╅瀵煎綋闈㈢‘璁や紭鍏堢骇鎺掑簭]
  钀界洏 round-trip: JSON 2330 瀛楃 鈫?鎭㈠ 6 鏉?  鈫?妗堜緥娌夋穩鏈哄埗锛堝懡涓鏁?鍙嶉闂幆锛変笌棰嗗煙鏃犲叧锛屽彲鎺ヤ换鎰忚鍒欏紩鎿庣粨鏋?```

## Demo 鍚勬璇存槑

| 娈?| 妯″潡 | 婕旂ず鍐呭 |
|----|------|----------|
| [0A] | rete | 璺ㄤ簨瀹為鎺э細order 脳 customer 脳 device 涓夌被浜嬪疄鍙橀噺缁戝畾 join锛屽懡涓悗鍔ㄤ綔淇敼浜嬪疄锛坰tatus=hold + 鏍囩绱Н锛?|
| [0B] | rete | 宸ュ崟璺敱锛氫袱鏉¤鍒欏叡浜?`customer.vip==true` 瀛愭潯浠讹紝Rete 鍙紪璇戜竴涓?alpha 鑺傜偣锛坅lpha 鏁?= 2 鑰岄潪 3锛?|
| [0C] | rete | 搴撳瓨杩為攣婵€娲伙細涓嬪崟鈫掓墸搴撳瓨鈫掍綆搴撳瓨琛ヨ揣鈫掕ˉ璐у悗涓嶅啀瑙﹀彂锛堝閲忎紶鎾?+ fire limit + 骞傜瓑淇濇姢锛?|
| [0D] | rete | OR/NOT 澶嶅悎鏉′欢锛歚||` 椤跺眰 OR 缁勶紙浠讳竴缁勬弧瓒冲嵆瑙﹀彂锛岀粍鍙嫭鍙峰寘瑁癸級锛沗!` 鍚﹀畾锛堝伐浣滃唴瀛樹腑涓嶅瓨鍦ㄦ弧瓒虫潯浠剁殑浜嬪疄鎵嶆弧瓒筹級锛岄粦鍚嶅崟鎷︽埅婕旂ず |
| [1] | evidence | 璇佹嵁鍒嗙骇锛堜功闈?璧勬簮/鍙ｅご/鐚滄祴锛? 缃俊搴﹀悎鎴?+ 缂哄け淇℃伅娓呭崟锛堝彲閫夌粍浠讹紝涓庡紩鎿庤В鑰︼紝绀轰緥鏁版嵁涓烘紨绀虹敤锛?|
| [2] | guardrail | 鍐崇瓥鍋忚鎶ゆ爮锛堣浆杩版斁澶?鎺緸鐭涚浘/浠呭嚟鎰熻绛夛級锛屼笉缁戝畾涓氬姟鍦烘櫙 |
| [3] | case | 妗堜緥搴撹惤鐩?round-trip + 鍛戒腑璁℃暟/鍙嶉闂幆鏈哄埗锛堜笌棰嗗煙鏃犲叧锛屽唴缃渚嬩负婕旂ず鏁版嵁锛?|

## 楠岃瘉璇存槑

- 鎵€鏈夎緭鍑轰负鏈粨搴?`main` 鍒嗘敮 `moon run main` 鐨勭湡瀹?stdout锛屾湭鍋氬垹鏀?- 鍚屼竴瑙勫垯闆?+ 鍚屼竴浜嬪疄娴佹亽寰楀悓涓€杈撳嚭锛堢‘瀹氭€ц鍒欏紩鎿庯紝鏃犻殢鏈烘€э級
- Rete 缃戠粶娴嬭瘯锛坙ib/rete/rete_test.mbt锛夎鐩栵細鍗曟潯浠惰Е鍙?/ 璺ㄤ簨瀹?join / 鍏变韩 alpha 鑺傜偣 / 鍐茬獊娑堣В锛坰alience鈫抯pecificity鈫抮ecency锛? 鍔ㄤ綔淇敼浜嬪疄杩為攣婵€娲?/ 骞傜瓑鑷Е鍙戜繚鎶?/ retract 娓呯悊 / 鏁板瓧姣旇緝杈圭晫 / 鏍囩绱Н / OR 缁勶紙鍚法浜嬪疄寮曠敤缁勫悎锛? NOT 鍚﹀畾锛堝惈榛戝悕鍗曟嫤鎴級
