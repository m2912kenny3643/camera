# 鳥眼／鳥頭模型隨公開 IPA 散布：0.5 研究

查核日期：2026-10-22。僅研究；後續新增獨立研究腳本與手動研究 workflow 選項，未修改 App 或 `docs/bird-release.json`。本機未執行發布者程式、未 unpickle／載入新權重，未開始訓練，也未聯絡發布者。

## 決策

**找到比現有候選更明確的「權重本身可散布」證據：I-MuPPET 的鴿子權重 deposit，CC BY 4.0。** 它確實輸出雙眼及喙／鼻等頭部關鍵點，但只證實鴿子領域；架構是較大的 Keypoint R-CNN，尚無 Core ML 匯出、廣泛鳥種或 iPhone 效能驗證。它是可落地的替代研究路線，不能立即宣稱是符合所有要求的手機鳥眼模型。[發布者權重說明](https://github.com/urs-waldmann/i-muppet/blob/a8588a792bd98dfc1513abcf809bfbdb40e30918/README.md#pre-trained-weights)、[鴿子權重 deposit](https://zenodo.org/records/7037589)、[該 deposit 授權 API](https://zenodo.org/api/records/7037589)。

**synthet 仍是工程成本最低的廣泛鳥類候選**：既有安全載入及 FLOAT32 轉換一致性已通過，實際 checkpoint 為 5.65 MB，但卡片 MIT／checkpoint AGPL 不一致、訓練資料用途證據仍未釐清。使用者接受 App 整體 AGPL，解決了「不願公開 App」的衝突，並不自行補足上述來源證據。兩條路都尚未通過 100 張獨立真實圖片與 iPhone 測試；本輪不解除正式 IPA 閘門。[既有結果與 CI](bird-eye-feasibility.md)、[目前發布紀錄](../bird-release.json)。

## 證據保存方式

原始公開模型卡、API 回應、程式碼及授權頁快照保存在 ignored `build/research/bird-bundling-0.5/`；`sources.json` 記錄每個 URL、HTTP 結果、大小與 SHA-256。此目錄不提交，也不放入公開 artifact。下文保留足以重新查核的固定 URL、版本、短原文及重要雜湊。動態 API／HTML 的雜湊只識別本次快照，不代表永久穩定。模型雜湊若只來自 LFS metadata，明確標示，不能稱為完整下載驗證。

## 1. synthet/eye-pose-v0：保留為主要工程候選，散布證據尚未閉合

### 固定模型與授權事實

- HF revision：`6e7bd361ba84b17d81f0fb4315a44a868df5b692`；本輪 API 仍指向此版本。[API](https://huggingface.co/api/models/synthet/eye-pose-v0)。
- `eye_pose_v0.pt`：5,654,984 bytes；已下載 checkpoint 的 SHA-256 `ec9e4b80a93eb6e2b21633e2ff2df30c49faa1eb7919dd24345c7dc295b2d1be`，與本輪固定版 LFS metadata 相符。[固定下載](https://huggingface.co/synthet/eye-pose-v0/resolve/6e7bd361ba84b17d81f0fb4315a44a868df5b692/eye_pose_v0.pt)、[固定檔案清單](https://huggingface.co/api/models/synthet/eye-pose-v0/tree/6e7bd361ba84b17d81f0fb4315a44a868df5b692?recursive=true&expand=true)。
- 模型卡原文 metadata：`license: mit`；卡片宣告基底 `ultralytics/yolo11n-pose`。固定卡片 1,763 bytes、SHA-256 `8b27fc580ae72f21a5b7b3abf5be890d90c6c8163ea78da724326d6cd5324913`。[固定卡片](https://huggingface.co/synthet/eye-pose-v0/raw/6e7bd361ba84b17d81f0fb4315a44a868df5b692/README.md)。
- 既有靜態 `pickletools` 紀錄在 checkpoint `best/data.pkl` byte offset 91 找到實際 `license` 值：`AGPL-3.0 (https://ultralytics.com/license)`；`version` 為 `8.4.67`。這是具體的衝突證據，不能只拿卡片 MIT 標籤覆蓋它。[本機既有研究紀錄](bird-eye-feasibility.md)。
- 固定 HF tree 只有 `.gitattributes`、README、checkpoint、`wildlife_bird.yaml`；固定版 `/LICENSE` 本輪 HTTP 404。相關程式碼最新 commit 仍是 `20bae89a25d923c56466fb1a0421572ad291e4a0`，其 pyproject MIT 宣告是程式碼來源證據，不是額外的 checkpoint 授權澄清。[程式 metadata](https://github.com/synthet/image-scoring-model/blob/20bae89a25d923c56466fb1a0421572ad291e4a0/pyproject.toml)。
- 上游固定版 LICENSE 是 AGPL-3.0；本輪檔案 SHA-256 `0d96a4ff68ad6d4b6f1f30f713b18d5184912ba8dd389f86aa7710db079abcb0`。[Ultralytics 8.4.67 LICENSE](https://github.com/ultralytics/ultralytics/blob/v8.4.67/LICENSE)。官方授權頁有公開完整來源的 AGPL 路線，但這不能替第三方資料或發布者的權限作保證。[官方授權說明](https://www.ultralytics.com/license#choosing-your-license)。

### 訓練資料與真正輸出

Caltech 原文："Their use is restricted to non-commercial research and educational purposes." 這是**來源影像**用途限制；官方也說影像著作權不屬於資料集發布者。此頁沒有明確的「已訓練權重可自由再散布」條款，也沒有明文在此頁判定一切衍生權重禁止散布。因此本研究將其列為未決來源條件，**不是直接斷言權重違法或不可散布**。本輪頁面 SHA-256 `c15eca84efc05c8d0c73cedcef2ed500604ee3d807bfc682ddcedbf5cd3f76b1`。[CUB 官方條件](https://www.vision.caltech.edu/datasets/cub_200_2011/#download)。

真正輸出為鳥身框加 `beak, left_eye, right_eye, head_top, left_shoulder, right_shoulder`。既有已測 Core ML 契約為 RGB 640×640、`pose_output [1,23,8400]`；App 目前的 `BirdPoseModel` 只接受這個契約，不能直接放入其他模型並沿用 decoder。[固定 schema](https://huggingface.co/synthet/eye-pose-v0/raw/6e7bd361ba84b17d81f0fb4315a44a868df5b692/wildlife_bird.yaml)、[App adapter](../../R6Camera/Camera/BirdPoseModel.swift)、[decoder](../../R6Camera/Core/BirdPoseObservation.swift)。

**現實下一步**：保留 AGPL 與 MIT 兩種原始證據，取得能說明該確切 checkpoint 轉換與公開二進位散布的來源依據，或由專業授權判讀決定是否足夠；此研究沒有聯絡任何人。在這之前可設計評測，但不得將未決狀態改成 verified。

## 2. I-MuPPET：權重明確標示 CC BY 4.0 的新候選

### 這次是權重授權，不是拿資料集授權代替

發布者 README 的「Pre-trained weights」直接連結以下兩個 deposit；record description 明確描述內容為預訓練權重。因此 API 的 `metadata.license.id: cc-by-4.0` 是**該權重發布物**的授權標示，不是別處 dataset 的標示。程式碼另有 MIT LICENSE，兩者分開保留。[固定 README L37–38](https://github.com/urs-waldmann/i-muppet/blob/a8588a792bd98dfc1513abcf809bfbdb40e30918/README.md#L37-L38)、[固定程式 LICENSE](https://github.com/urs-waldmann/i-muppet/blob/a8588a792bd98dfc1513abcf809bfbdb40e30918/LICENSE)。

| 權重 deposit | 版本／檔案 | 公開授權與完整檔校驗碼 |
|---|---|---|
| [7037589，鴿子](https://zenodo.org/records/7037589) | v1，2022-08-31；`weights.zip` 1,312,779,841 bytes | API `cc-by-4.0`；MD5 `4ea3c58e1c2335ae4e8a32193f93744f` |
| [7037558，牛鸝與鼠](https://zenodo.org/records/7037558) | v1，2022-08-31；`weights.zip` 1,313,523,170 bytes | API `cc-by-4.0`；MD5 `29f1c2e9fe1bb67880a6ccaf5a575012` |

鴿子 [record API](https://zenodo.org/api/records/7037589) 本輪快照 SHA-256 `f845ed5b3da8d71b75c775e260d9ab30d396538aeabbd92c01fb59256ae926d3`；牛鸝／鼠 [record API](https://zenodo.org/api/records/7037558) 為 `c24286c37dc8aa4ba78a9290fe98996c7d6044e8684ce8d8758c25cfce07430f`。這兩個 MD5 是發布者的整包校驗碼，本輪沒有下載整包，不能宣稱已驗證。

### 已以 HTTP Range 證實可單獨取出一個 checkpoint

對[鴿子 zip](https://zenodo.org/api/records/7037589/files/weights.zip/content) 的尾端 Range 回 HTTP 206：`bytes 1312714305-1312779840/1312779841`。ZIP directory 有 9 entries，其中 6 個 checkpoint。各 `.pt` 解壓後都是 236,764,912 bytes；不需要下載全部 1.3 GB：

| entry | local header offset | 壓縮 bytes | CRC32 |
|---|---:|---:|---|
| `weights/muppet_600.pt` | 1,094,136,192 | 218,642,592 | `2cb9597d` |
| `weights/muppet.pt` | 875,287,954 | 218,848,191 | `f1791d74` |
| `weights/3dbr_comparison/pigeon.pt` | 92 | 218,991,586 | `67b62148` |

其餘是 `weights/dlc_comparison/pigeon_split_1.pt`、`pigeon_split_2.pt`、`pigeon_split_3.pt`。目錄存於 ignored `imuppet-weights-directory.json`。**CRC32 只證實 ZIP entry 資訊，不能替代完整權重 SHA-256。** 下一次可 Range 下載所選 entry 的 local header＋約 219 MB deflate payload，串流解壓與 CRC 校驗後自行計算完整 SHA-256；HTTP 若不回 206 或總長／版本改變，停止，不靜默改成整包下載。

本輪只另外取 `muppet_600.pt` 開頭 262,144 bytes 的壓縮範圍（Range start `1094136192`），SHA-256 `180400410d16f42dd8099b4856ad7209d01d72462d2724d6da390c0f738aa6f5`。有限解壓後的內層是 PyTorch ZIP，`archive/data.pkl` 可由 `pickletools.genops` 讀完，其 GLOBAL 僅見 `collections.OrderedDict`、`torch.FloatStorage`、`torch._utils._rebuild_tensor_v2`；鍵包含 `backbone.body.conv1.weight`。這是 **state_dict 型結構的靜態證據**，不是已安全載入整個模型；完整檔取得後仍須掃描全部 pickle／ZIP 與 tensor budget，再用 `weights_only=True`。

### 後續實作查驗：單檔完整取得與靜態張量 audit 已完成

以上「只取前綴」描述初次查核；經使用者授權繼續後，已於 2026-10-22 以**一個精確 Range**取得該 checkpoint，無重試、沒有下載整包。HTTP 回應為 206，`Content-Range: bytes 1094136243-1312778834/1312779841`；這正是 ZIP entry 的 deflate payload，不包含其他 checkpoint。串流解壓設大小上限，驗證 deflate 完整結束、預期大小及 central directory CRC32；失敗最多重試三次，HTTP 200／範圍不符會拒收。

| 實測項目 | 結果 |
|---|---|
| 原始來源 | [Zenodo7037589 `weights.zip`](https://zenodo.org/api/records/7037589/files/weights.zip/content)，entry `weights/muppet_600.pt` |
| 壓縮 payload | 218,642,592 bytes；SHA-256 `e780e90c0bae805761ff61f9eac63359722a3e75eecfbe90cb1a635575f51519` |
| 完整 checkpoint | **236,764,912 bytes**；SHA-256 **`dab61b233202a4ee474d07d9c112a9f360b1c554bff37e4adec89a063d44cd1e`** |
| 外層 entry CRC32 | `2cb9597d`，與 ZIP directory 相符 |
| 內層 PyTorch ZIP | 315 entries；所有 entries 的 ZIP CRC 全通過；無重複檔名、加密、絕對／越界路徑；沒有解壓到任意路徑 |
| `archive/data.pkl` | 55,460 bytes；SHA-256 `1fc6d806bc0a61757f4b71ce73baa36211b7abedd40ce0971269221e305d0c4e` |
| state_dict | **313 tensors，全部 FloatStorage／float32**；59,161,568 tensor elements，236,646,272 tensor bytes；313 個不同 storage，全部 offset0 |
| 執行限制 | 未 import torch、未呼叫 `torch.load`、未呼叫 pickle 的 GLOBAL／REDUCE 目標、未執行發布者程式；沒有載入模型或跑推論 |

靜態 audit 使用 `pickletools.genops` 加封閉的 symbolic interpreter：把 GLOBAL 轉成純描述符，僅接受已觀察到的三個 GLOBAL 字串；`OrderedDict` 只映射為本機基本 dictionary；`_rebuild_tensor_v2` 只映射為 storage/offset/shape/stride 描述，**沒有呼叫該函式**。BUILD 只接受 `_metadata` 字典，不執行 `__setstate__`。未知 opcode／callable 一律失敗。逐個 BINPERSID 核對其 storage 檔案長度等於 `count×4`、shape／stride／offset 可落在 storage 範圍內；最後 STOP 必須恰好位於 pickle 結尾。此方法確認結構與容量，沒有驗證所有數值是否有限，也不能替代後續受限實際載入。

完整 313 個 keys／shape／stride／storage 對照已寫入 ignored `imuppet-checkpoint-static-audit.json` 與 `imuppet-tensor-shapes.csv`。以下實測形狀可供重建 torchvision 模型時比對：

| state_dict key | float32 shape |
|---|---|
| `backbone.body.conv1.weight` | `[64,3,7,7]` |
| `backbone.fpn.inner_blocks.0.weight` | `[256,256,1,1]` |
| `rpn.head.conv.weight` | `[256,256,3,3]` |
| `rpn.head.cls_logits.weight` | `[3,256,1,1]` |
| `rpn.head.bbox_pred.weight` | `[12,256,1,1]` |
| `roi_heads.box_predictor.cls_score.weight` / `.bias` | `[2,1024]` / `[2]` |
| `roi_heads.box_predictor.bbox_pred.weight` / `.bias` | `[8,1024]` / `[8]` |
| `roi_heads.keypoint_predictor.kps_score_lowres.weight` / `.bias` | **`[512,7,4,4]` / `[7]`** |

七個輸出通道與發布者七點 schema 一致，兩個 detection classes 與 pigeon＋background 一致；這仍是靜態相容性證據，不是成功重建或準確度結果。storage 裝置記錄為 `cuda:0`，後續研究載入需明確 `map_location="cpu"`。本檔保留舊式 `rpn.head.conv.weight`／FPN key 名稱；現代 torchvision 版本的 key 命名可能不同，不能在未核對完整 mapping 前用 `strict=False` 忽略 missing／unexpected keys。

本機素材皆位於 ignored `build/research/bird-bundling-0.5/`，沒有權重提交或 artifact：

| 查核紀錄 | bytes | SHA-256 |
|---|---:|---|
| `imuppet-checkpoint-retrieval.json` | 907 | `ce4ca750936001d3bd7977419ef131ea77af33708b052b88d444063019cd09dc` |
| `imuppet-checkpoint-static-audit.json` | 113,783 | `622bda68fb13ec73249e14fe1e3fcebcb9e2b9f2f696535256befd01d5beb8dd` |
| `imuppet-tensor-shapes.csv` | 26,125 | `e1f175d6f240237abf824cb0fcfa2c30babbec28abc73182239a39e5439259b8` |

`retrieve_single_checkpoint.py` 和 `audit_checkpoint.py` 也僅保留為 ignored、可閱讀的研究操作紀錄，不是 App 或正式發布流程。完整 SHA-256 是本次實際取得的單檔計算值；尚未獨立下載並核對 1.3GB archive 的整包 MD5，不能混稱兩者皆通過。App／release gate 未修改。

### 獨立 opt-in macOS 實驗：首次探測失敗，FrozenBN 修正待重跑

新增 [research_imuppet_export.py](../../scripts/research_imuppet_export.py)，沿用 [bird-research.yml](../../.github/workflows/bird-research.yml) 的手動工作流程；`candidate` 選項為 `synthet`（預設不變）或 `imuppet`。手動 dispatch 可選擇實驗分支。權重／traced 模型／Core ML package 只寫 ignored `build/research/imuppet/`；唯一新增上傳項目為 `build/imuppet-research-report.json`，沒有權重或 IPA artifact。GitHub runner 仍需真正執行，不能把腳本存在當成功。

I-MuPPET 分支只安裝共同的固定環境 `torch2.7.0 / torchvision0.22.0 / coremltools9.0 / numpy1.26.4`，不安裝或 import Ultralytics、發布者模型程式或 SORT。實驗順序：

1. 取得上述固定 Range，大小／CRC32／壓縮與解壓 SHA-256 全相符才保留。既有本機檔案亦重新核對完整大小／hash。
2. 掃描完整 ZIP、全部 CRC、固定 pickle SHA／長度、封閉 opcode／三個 GLOBAL 與 storage budget；再且僅再用 `torch.load(weights_only=True, map_location="cpu")`，不添加 custom safe_globals、不允許寬鬆重試；驗證所有313 tensor型別、dtype、59,161,568總元素、finite及輸出頭形狀。
3. 純 torchvision 明確建構 `resnet_fpn_backbone(backbone_name="resnet50", weights=None, norm_layer=FrozenBatchNorm2d, trainable_layers=0)`，再交給 `KeypointRCNN(..., num_classes=2, num_keypoints=7)`，保留 checkpoint `_metadata`，**strict=True** 載入。這是下方首次結果後的修正，不能把先前全None factory的普通BN當成相同架構。舊FPN／RPN版本轉換只由固定版官方 `_load_from_state_dict` 執行，不自行吞 missing／unexpected keys。[FPN migration](https://github.com/pytorch/vision/blob/v0.22.0/torchvision/ops/feature_pyramid_network.py#L100)、[RPN migration](https://github.com/pytorch/vision/blob/v0.22.0/torchvision/models/detection/rpn.py#L37)。
4. 標準RGB0…1單張推論（灰、漸層、固定seed雜訊，加上可取得的官方鴿子 smoke），檢查五個輸出形狀與有限值，報CPU時間；只有smoke，不構成準確度驗收。[官方輸入契約](https://github.com/pytorch/vision/blob/v0.22.0/torchvision/models/detection/keypoint_rcnn.py#L26)。
5. trace完整RCNN，保留 resize／normalize／FPN／RPN／ROI／NMS，記錄operator名稱。優先從非空的官方鴿子case trace；`check_trace=False` 只避開隱藏的重複驗證，**仍明確比較所有輸入的 eager→trace 輸出**。shape、labels、finite不相符或數值超過既定門檻會失敗，不跳過再宣稱成功。
6. 嘗試完整圖 `ct.convert`，FLOAT32、固定`image_tensor[1,3,640,640]`，iOS18 minimum（研究部署目標，不是 App 改版）。缺必要算子時記錄具體例外並停止；不砍ROI／RPN或偽造輸出。成功才做CPU Core ML所有輸入parity；boxes／keypoints最大絕對誤差門檻0.01像素、scores0.0001、keypoints_scores0.001、labels完全相同，空輸出仍要求shape一致。這些是研究數值門檻，不是鳥眼準確度門檻。**沒有非空的官方鴿子case時，即使所有空輸出parity通過，也禁止 `experiment_passed`**，記錄 `empty-positive-coverage`；圖片不可取或沒有辨識到時仍允許嚴格載入／trace／Core ML可行性探測。

smoke 來源為[官方 project page](https://urs-waldmann.github.io/i-muppet/) 實際引用的 [framework.jpg](https://urs-waldmann.github.io/i-muppet/imgs/framework.jpg)，225,202 bytes、2244×472、SHA-256 `b9d1970bf4a4a2c6f92c2173582c55e081a7bab4ac3f4dc04b46dbc34605bb91`。本輪已目視確認左側是真正、沒有預測框的輸入鴿子照片；只裁其內部 `xyxy=(34,34,354,354)`，雙線性放大為640-square並轉RGB0…1。若來源更新／hash不符則拒用。原圖僅存 ignored，**不上傳、不進App、不訓練、不計入100張獨立評測**；此figure可能與訓練資料同源，未建立照片的獨立散布授權，不把code MIT當成照片權利證據。本例只回答完整RCNN是否確實產生並保留非空instances，不回答泛化或眼點正確率。

本機 Windows 已通過 `py_compile` 及 inspect-only（實際完整checkpoint）的全部靜態檢查；本機沒有執行torch載入、標準推論、tracing或Core ML轉換。首次macOS結果見下節；FrozenBN修正版再次通過本機 `py_compile`，尚待新CI。macOS實際命令為 `R6_BIRD_PERSONAL_RESEARCH=1 python scripts/research_imuppet_export.py --convert`。若只要本機重驗既有素材，可加 `--checkpoint build/research/bird-bundling-0.5/muppet_600.pt`；預設不帶`--convert`只做靜態查核。

### 實測 39805007324：嚴格載入通過，不等於鳥眼模型可用

[macOS研究 run39805007324](https://github.com/m2912kenny3643/camera/actions/runs/39805007324) 的實際 JSON 已下載查閱（ignored `build/output/0.5-final/bird-research/imuppet-research-report.json`，SHA-256 `adfcb35e33249a475cdb452cd7b5cd977bfdb6db52d886ec4ee7438a9964836d`）：

- 安全載入與313-tensor **strict=True** 載入通過，missing／unexpected keys皆空。
- 灰、漸層、雜訊、官方鴿子裁圖**四例全部 `boxes [0,4]`**。四例trace parity通過只代表空輸出一致；`positive_output_coverage` 明確為false，沒有 `experiment_passed`，不能據此說明一般眼／頭可用。
- 完整 Core ML 轉換實際失敗：`NotImplementedError: PyTorch convert function for op 'torchvision::roi_align' not implemented.` 沒有匯出或手機推論證據。

#### 已修正但尚未重跑的架構差異

原作者 [network_utils.py L16–24](https://github.com/urs-waldmann/i-muppet/blob/a8588a792bd98dfc1513abcf809bfbdb40e30918/utils/network_utils.py#L16) 用 `pretrained_backbone=True`。torchvision0.22 [官方factory L430–436](https://github.com/pytorch/vision/blob/v0.22.0/torchvision/models/detection/keypoint_rcnn.py#L430) 依 `weights`／`weights_backbone` 是否非None決定norm：有預訓練來源用FrozenBatchNorm2d，兩者全None則普通BatchNorm2d。**strict載入成功不會自動把module類別改成FrozenBN**，因此首次實驗的架構一致性沒有建立，不能將零detections直接歸因於checkpoint失效。

目前腳本使用[官方 `resnet_fpn_backbone` L63–107](https://github.com/pytorch/vision/blob/v0.22.0/torchvision/models/detection/backbone_utils.py#L63) 明確設定FrozenBN而且 `weights=None`、`trainable_layers=0`，再建立KeypointRCNN，沒有下載任何ImageNet／COCO額外權重。要求全模型53個FrozenBN、普通BN=0；strict載入前／後記錄norm完整類別與epsilon。原有hash、budget、strict=True、非空鴿子coverage閘門、完整RPN／ROI／NMS都不變。FrozenBN修正是有來源依據的重建修正，**尚未測得它會產生非空detections**。

### 保留ROIAlign的下一條技術路線

**Core ML 原生 converter 現況**：固定 [coremltools9.0 Torch ops](https://github.com/apple/coremltools/blob/9.0/coremltools/converters/mil/frontend/torch/ops.py) 沒有 `roi_align` 註冊，本次CI已實際證明該算子阻擋。Apple官方建議對缺少的op寫 [MIL composite operator](https://apple.github.io/coremltools/docs-guides/source/composite-operators.html)；舊NeuralNetwork builder的 [crop_resize](https://apple.github.io/coremltools/_modules/coremltools/models/neural_network/builder.html#NeuralNetworkBuilder.add_crop_resize) 描述ROIAlign可由crop-resize加pooling構成。這提供自訂等價轉換的方向，**沒有提供適用本完整RCNN的現成、已驗證converter**。

不能把單次crop/resize當成已等價的ROIAlign：還需驗證sampling ratio、aligned=False的座標／小ROI夾限、每個FPN level、空ROI與可變ROI數、dtype及keypoint head的不同pool尺寸。[Apple repo issue2479](https://github.com/apple/coremltools/issues/2479) 的社群範例就碰到空ROI形狀／dtype問題；它不是官方保證或可直接照抄的解法。Apple [custom operator文件](https://apple.github.io/coremltools/docs-guides/source/custom-operators.html#step-4-implement-classes-in-swift) 另明示custom layer只支援NeuralNetwork backend，**不支援MLProgram**。切換backend再寫Swift算子是另一個實作工程，不是一行註冊就完成，也不能跳過完整正例parity。因此本輪沒有添加猜測性的ROI converter。

**較有原始資料支持的替代研究：完整ONNX → ONNX Runtime CPU，再評估iOS。** [torchvision0.22官方模型文件](https://github.com/pytorch/vision/blob/v0.22.0/torchvision/models/detection/keypoint_rcnn.py#L392) 明確描述固定batch／固定input尺寸可匯出ONNX；[官方symbolic註冊 L69–98](https://github.com/pytorch/vision/blob/v0.22.0/torchvision/ops/_register_onnx_ops.py#L69) 對 `torchvision::roi_align` 有opset16的ONNX `RoiAlign`，保留sampling ratio、spatial scale，依aligned選 `half_pixel`／`output_half_pixel`，NMS也有官方symbolic。這比無現成CoreML註冊更具體，但本checkpoint尚未實際匯出ONNX，不能先宣稱成功。

- [ONNX Runtime1.22 CPU kernel表 L358](https://github.com/microsoft/onnxruntime/blob/v1.22.0/docs/OperatorKernels.md#L358) 明確有RoiAlign16+、float32／float64與int64 batch indices。首次研究應使用完整CPU runtime，保留ROI／NMS，不先砍operators做minimal build。用相同FrozenBN PyTorch eager輸出比對ONNX模型的全部輸出；必須有非空官方鴿子結果並另測不同instance數，不能再以全空輸出通過驗收。
- 官方提供 [iOS `onnxruntime-objc`](https://onnxruntime.ai/docs/get-started/with-obj-c.html)，可透過bridging header從Swift呼叫；[mobile說明](https://onnxruntime.ai/docs/tutorials/mobile/) 指預建mobile package包含完整ONNX算子集。[iOS build](https://onnxruntime.ai/docs/build/ios.html) 有arm64裝置支援。這是獨立runtime路線，**不需要把ONNX再轉成CoreML**。
- [ORT1.22 LICENSE](https://github.com/microsoft/onnxruntime/blob/v1.22.0/LICENSE) 是MIT；runtime MIT不會替模型／照片重新授權，仍各自保留模型CC BY4及相關notices。CoreML EP只接管支援的子圖，[官方支援表](https://onnxruntime.ai/docs/execution-providers/CoreML-ExecutionProvider.html#supported-operators)未列RoiAlign，不能承諾全圖或ROI跑ANE。
- 即使ONNX CPU parity通過，約237MB權重及完整RCNN對手機記憶體／延遲的成本仍需實測；不得據CPU kernel存在宣稱適合即時追焦。下一步是隔離的ONNX CPU研究，不是Appintegration或發布model artifact。

本輪版本來源已保存在 ignored `normalization-ort-sources.json`，其中factory SHA-256 `e07c7046ba7c9497ddca2f0adde06ae2fb2d6d1acbf1b65cd87861fa95478ec2`、coreml9 ops `eaa4573cb55028fd08e2e73c61e45fc6d2a337702a48448ee1b223cd6190edd2`、ORT1.22 LICENSE `2f07c72751aed99790b8a4869cf2311df85a860b22ded05fa22803587a48922c`。未新增App依賴或改發布閘門。

### 真正眼／頭點、單張推論依賴及限制

程式碼固定 commit `a8588a792bd98dfc1513abcf809bfbdb40e30918`：

- [pigeon_model.py L7–9](https://github.com/urs-waldmann/i-muppet/blob/a8588a792bd98dfc1513abcf809bfbdb40e30918/models/pigeon_model.py#L7) 列出七點：`head_beak, head_nose, left_eye, right_eye, left_shoulder, right_shoulder, body_tail`。是真正標註的雙眼與頭部點；沒有 crown／head_top，不能改名假裝有。可從可靠的眼、喙、鼻點形成 landmark-derived head region；缺點時只保留實際鳥身框。
- [network_utils.py L15–36](https://github.com/urs-waldmann/i-muppet/blob/a8588a792bd98dfc1513abcf809bfbdb40e30918/utils/network_utils.py#L15) 使用 torchvision `keypointrcnn_resnet50_fpn`，2 classes（含背景）、7 keypoints、ImageNet pretrained backbone；權重是 state_dict。這不是現有 synthet YOLO decoder 的替代檔案。
- [單張 helper L54–90](https://github.com/urs-waldmann/i-muppet/blob/a8588a792bd98dfc1513abcf809bfbdb40e30918/utils/network_utils.py#L54) 將 OpenCV BGR 轉 RGB、ToTensor 到 0…1，然後 `network([image])[0]`。辨識與 keypoints 同一模型，**單張推論不需要額外 YOLO、SORT、影片讀取或重建 3D**；那些是範例系統其他層。模型自己的 resize／normalize／RPN／ROI／NMS 仍然是推論圖的一部分，不能省略後聲稱相同結果。
- [原始 prediction handling L91–107](https://github.com/urs-waldmann/i-muppet/blob/a8588a792bd98dfc1513abcf809bfbdb40e30918/utils/network_utils.py#L91) 有 boxes／scores／keypoints。應在新 adapter 另外查實所用 torchvision 版本的 per-keypoint 分數語義；不能把一般 `(x,y,visibility)` 的第三欄自行解釋成 synthet 的 sigmoid confidence。
- [發布者適用性說明](https://urs-waldmann.github.io/i-muppet/#additional-results) 明確展示鴿子資料及失敗情況；不得從鴿子結果宣稱所有野鳥。牛鸝權重的程式 schema 只列匿名 `keypoint_0…11`，在取得註解映射前不應假定其中有左右眼。[cowbird schema](https://github.com/urs-waldmann/i-muppet/blob/a8588a792bd98dfc1513abcf809bfbdb40e30918/models/cowbird_model.py)。

**判定**：此為本輪最清楚的可散布權重候選；保留 attribution、CC BY 4.0 連結及轉換修改說明，再分開處理程式 MIT 與依賴聲明。但「有發布者授權」並不是對全部上游權利的保證；來源明示 ImageNet backbone，仍應記錄其版本／來源條件。約 237 MB 的 FP32 checkpoint、RPN／ROIAlign／NMS 和可變 instances 是手機轉換／延遲風險，沒有實際匯出不能保證可用。此時不新增會被誤認為已可轉換的正式 workflow，也不把未測模型包入 IPA。

## 3. 其餘候選的具體證據／阻擋

### Dryad BirdGaze 與 Zenodo PoseEstimation：找到程式包，但沒有權重

[Dryad API](https://datadryad.org/api/v2/datasets/doi%3A10.5061%2Fdryad.bk3j9kdpb) 的 software relatedWork 指向 [Zenodo 15802821](https://zenodo.org/records/15802821)，修正舊研究只看到 README 提及、未找到下載的位置。Dryad 資料 license 是 CC0；**Zenodo 程式包則明確標 MIT**，兩者不是同一份發布物。[Zenodo metadata](https://zenodo.org/api/records/15802821)。

已下載 `PoseEstimation.zip`，14,592,679 bytes，MD5 `7e38de60b818fdf2f3766b5f001c0805`，本機 SHA-256 `90a0604463bd3ae2c1407e1812739519aba74a19083ff7971a5ca69e3065a3cd`。只列 ZIP／讀文字，沒有執行。180 entries、解壓總量 17,335,206 bytes；`models/` 僅有 `base_backbone.py, cross_attn.py, pose_hrnet.py, pose_resnet.py, pose_vhr.py, vit.py, __init__.py`，**沒有 checkpoint**。最大部分實際是內附 cocoapi 的 Git pack 與編譯殘留；不是隱藏的可用鳥模型。

`PoseEstimation/experiments/inference.yaml` 的 `TEST.MODEL_FILE` 指向作者本機 `D:\BirdAnalysis\PoseEstimation\models\trained\4PointsHRNet\model_best.pth`，檔案不在包內；`main.py` 的 `YOLOv8Bird.pt` 也不在包內。config 是 4 joints、256×256 input、64×64 heatmaps；main 實際 import `models.pose_hrnet.get_pose_net`（config NAME 卻仍是 pose_vhr）。main 的單張前處理為 bbox 中心／尺度 affine warp、ToTensor、ImageNet mean/std，然後 heatmap decode。原文註解與發布者說明將四點描述為頭、左眼、右眼、喙。[官方檔案下載](https://zenodo.org/api/records/15802821/files/PoseEstimation.zip/content)。

**阻擋**：沒有實際權重可轉換；Zenodo MIT metadata 不能授權不存在的 checkpoint，也不能覆蓋內附第三方 COCO／Ultralytics 等未知範圍。保留為尋找發布者日後補件的來源，不能列為 ready-to-bundle。

### DeepLabCut SuperAnimal-Bird：真實公開模型，授權尚不足

修正舊 note「沒有 bird model」的過時結論。[HF 固定 revision](https://huggingface.co/DeepLabCut/DeepLabCutModelZoo-SuperAnimal-Bird/tree/04caf827dde559778d347a46d0e237719eb26fa3) `04caf827dde559778d347a46d0e237719eb26fa3` 有：

| 檔案 | bytes | 發布者 LFS SHA-256（未下載全檔） |
|---|---:|---|
| `superanimal_bird_resnet_50.pt` | 103,388,474 | `5638eefbe88222430d13b48a189655a3d6bb0d7f891099de9a60c4310f77d613` |
| `superanimal_bird_ssdlite.pt` | 9,138,778 | `7c45e30949c0d3ecd79224da09d8a78326497a91c47785f5fe5c22e2e48b1f4b` |
| `superanimal_bird_fasterrcnn_mobilenet_v3_large_fpn.pt` | 76,036,115 | `9912a9cb9bd0f9a42762fe1774030df711bb7ddb0426eba74fcae0fcf46afc09` |

[模型卡](https://huggingface.co/DeepLabCut/DeepLabCutModelZoo-SuperAnimal-Bird/raw/04caf827dde559778d347a46d0e237719eb26fa3/README.md) 僅 149 bytes，SHA-256 `d885d04af0e9b8bc1520a3202f1d154d7f82fd0c76f0ed3864fa1ce35511470f`，沒有 license metadata；固定 tree 沒 LICENSE，固定 `/LICENSE` HTTP 404。官方 [bird config](https://github.com/DeepLabCut/DeepLabCut/blob/fa5a8c36100c85300b7d4a534deb38d7bd8b2fa8/deeplabcut/modelzoo/project_configs/superanimal_bird.yaml#L21) 確實含 `left_eye/right_eye/bill/crown/forehead/nape` 等點。然而[官方授權說明](https://deeplabcut.github.io/DeepLabCut/#license) 的原文是 "SuperAnimal models are provided for research use only (non-commercial use)." 一般攝影 App 的公開散布未被此句明確允許；不能用 DLC 程式 LGPL 或其他 SuperAnimal 的 modified MIT 卡片代替。

### SuperBirdEye／SuperPicky：有 GPL 標示，但仍有來源／資料問題

原作者 [SuperBirdEye](https://github.com/triple333sR9/SuperBirdEye) commit `cdf4cc3c69d8957c5ad420980577b89bfd29853d` 說明輸出左右眼、喙，基於 CUB；本輪 GitHub API 的 license 是 null。共同開發者的[模型發布庫](https://huggingface.co/jamesphotography/SuperPicky-models/tree/291d62879f65932cc3e984ec860c1f75a33fdc76) 有明確卡片 `license: gpl-3.0`，不能誤稱所有地方都沒授權；但同一發布庫混合多種第三方權重，卡片只有 28 bytes，沒有逐檔來源／權限說明。

`cub200_keypoint_resnet50_slim.pth` 99,098,270 bytes，LFS SHA-256 `25bee11a4846e9065185bf22512e0ce4f81a62da79aece8f1683209f375904a6`；同名 ONNX 98,698,988 bytes，LFS SHA-256 `2b62d30e36357b807a909fb22ae55323f768feb2957fbf4ecbd840bd7525f514`。未下載全檔。卡片 SHA-256 `1f4bbfeff4d3e7e3e9dd3ae9e8879d7069a84543f2eca5f1edb539d89aed6c03`。[固定卡片](https://huggingface.co/jamesphotography/SuperPicky-models/raw/291d62879f65932cc3e984ec860c1f75a33fdc76/README.md)。

**判定**：不是必然不能用；但原作者至發布庫的授權範圍未明確、CUB 問題與 synthet 相同、沒有獨立 head_top，且目前 App 契約不相容，沒有比 I-MuPPET 清楚或比 synthet 省工。

### VHR-BirdPose、PigeonSuperModel、Roboflow

- [VHR-BirdPose 固定 README](https://github.com/LuoXishuang0712/VHR-BirdPose/blob/dc08974a8fc3ccad15e18d041ea0c02bebb34f92/README.md#pretrained) 有外部 Drive／百度權重連結；固定程式 LICENSE MIT，但沒有明確說外部 checkpoint 採同一授權。保留 23 joints／真眼／頭點的來源線索，未把外部檔案算成已驗證權重。[LICENSE](https://github.com/LuoXishuang0712/VHR-BirdPose/blob/dc08974a8fc3ccad15e18d041ea0c02bebb34f92/LICENSE)。
- [PigeonSuperModel 官方教學](https://pigeonsupermodel.com/HowToPigeonSuperModel.html) 有真正 left/right eye、head 與直接模型 tar.gz URL；[官方條件頁](https://pigeonsupermodel.com/GetInTouch.html) 同時說 MIT 及 "intended for research/academic use only"。本輪 GitLab API／LICENSE 連線逾時，未取得 tar.gz 或 checkpoint 校驗碼。用途文字需釐清，不能只摘 MIT。
- [Roboflow Bird Head Pose](https://universe.roboflow.com/bird-annotation/bird-head-pose-estimation) 有 `/9` deployed keypoint model；CC BY 4.0 的引用段落明確指 dataset，未明確指該權重。現行 [Roboflow 方案](https://roboflow.com/pricing) 允許各方案透過 Inference／MCP 下載部分模型，**舊的「一定要付費才能下載」說法已不可靠**；實際可下載性與公開 IPA 再散布範圍仍須針對此模型查明。未使用帳號或 API key 取得權重。

## 執行順序與進度

### 完整 ONNX／CPU 實驗：已通過數值比對，尚非手機功能完成

[run 39823277101](https://github.com/m2912kenny3643/camera/actions/runs/39823277101) 來源 `b2fe76a53ba6e14b2616a021f35aceed291d2f43`，PyTorch 2.7.0／torchvision 0.22.0／ONNX 1.17.0／ORT 1.22.0、macOS arm64 CPU、2 inference threads。使用作者完整前處理及 FrozenBN，strict load 零 missing／unexpected keys。完整模型保留 8 個 RoiAlign、2 個 NonMaxSuppression 與動態 instance 軸，ONNX checker 通過；沒有砍掉 RPN／ROI／NMS。

匯出檔 236,836,457 bytes，SHA-256 `33e0c75b7babe8c114ef6e6ceb0361db2452481af97b929ef2ea769eb39c4839`。未上傳權重／模型檔；僅上傳並核對 JSON，[完整結果](imuppet-onnx-result-0.5.json)。灰階／漸層為0個候選、雜訊1個、官方鴿圖2個；這證明輸出數量變化時的數值路線，**不是鳥類準確率**，鴿圖兩個候選也不代表兩個正確目標。官方鴿圖的眼／其他關鍵點最大差 `0.0000763` pixel，keypoint score 最大差 `0.0000839`，四案例均在原訂門檻內。

各案例一次 warm-up 後僅測3次，CPU median 1711–1830 ms／張；鴿圖 1830 ms，最大1850 ms。它含模型內 resize／RPN／ROI／NMS，但不含外部解碼／影像準備，不能當 iPhone 端到端 latency、P95 或即時追焦能力。100張獨立真實圖與手機持續使用均未執行。完整圖可在 ORT 執行的路線已驗證；iOS runtime 整合、精度／物種泛化、記憶體與速度最佳化仍未完成，不封裝入本次驗證 IPA。

此前無額外 Normalize 的 ONNX probe run 39822863183 只可作舊前處理的診斷，不作功能驗收依據。Core ML 9 的 `torchvision::roi_align` 缺少 converter 仍是另一個實際阻擋；不能以本次 ONNX 成功宣稱 Core ML 也已完成。

### 完整前處理的補充核對

後續核對原作者固定 commit 的 [video_stream_utils.py](https://github.com/urs-waldmann/i-muppet/blob/a8588a792bd98dfc1513abcf809bfbdb40e30918/utils/video_stream_utils.py) 發現：非 COCO 的鴿子路徑在 RGB／ToTensor 之後，另呼叫 `normalize_tensor_image(mean=(0.5,0.5,0.5), std=(0.5,0.5,0.5))`，才送入 detector 自己的 transform。只看 `infer_one_image` helper 不足以重建作者完整流程。研究 wrapper 已將這一步納入圖內，外部輸入仍為 RGB 0…1；原 detector resize／ImageNet normalize／RPN／ROI／NMS 皆保留。

因此 run 39805007324／39806932373 的全空輸出不可用來判斷原模型辨識能力；這兩輪的 strict-load 與 Core ML `torchvision::roi_align` 不支援紀錄仍是實際探測結果，但不代表正確前處理後的整體準確度。新的完整前處理實驗另記結果，仍不得省略真實圖片／真機評估。

1. **已完成** I-MuPPET `weights/muppet_600.pt` 單檔 Range 取得、完整 SHA-256／CRC32、靜態 pickle 與 tensor shape audit，結果見上方。CC BY 4.0 attribution、轉換修改說明仍應隨未來轉換成果保留。沒有下載全部 1.3 GB，也沒有執行任何 loader。
2. 在隔離的 opt-in macOS 研究工作流程試驗純 torchvision 重建＋`weights_only=True`，不自動下載 ImageNet／COCO 額外權重；明確固定 torchvision 與 PyTorch。先證實完整 state_dict 可重建，再調查 RPN／ROIAlign／NMS 的 Core ML 支援及固定尺寸輸出策略；遇不支援算子記錄具體 blocker，不移除必要運算後冒稱 parity。
3. 先測鴿子，按明確物種範圍報告；至少 100 張獨立、可合法用於評測且人工標記的真實圖片，包含小眼、側面、遮擋、多鳥與負例。分開報告眼點誤差、錯指他鳥、眼不可見時誤報、head/body fallback 與 PyTorch→Core ML 數值一致性。confidence 門檻須以實測校準，不能把任何輸出座標當成可靠眼點。
4. iPhone 17/iOS 27 上測端到端 P50/P95 latency、丟幀、持續運作熱狀態及拍攝同時執行的影響。只有實際通過後才考慮另一個明確型別的 adapter／decoder，沿用現有單一身分 tracking；不把鳥身框冒充鳥頭或推造眼睛。
5. 依上述結果決定：繼續釐清 synthet 的更小模型、僅限鴿子的清楚標示支援，或仍維持模型不隨正式 IPA 發布。**目前沒有充分證據宣稱「一般野鳥眼／頭 + 可公開散布 + 已測 iPhone 效能」三者同時完成。** 不自行啟動大型訓練，不修改 release verified 欄位。
