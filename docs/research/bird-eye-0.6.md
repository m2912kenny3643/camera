# 0.6 鳥眼：可用性、散布證據與獨立評測

查核：2026-10-23（Asia/Taipei）。本輪讀取原始模型文件、原始資料集條件與作者程式；沒有聯絡作者、啟動訓練、下載大資料集或修改發布閘門。

## 結論

**目前仍沒有同時通過散布條件、100 張獨立真實圖片與 iPhone 即時效能的模型。** 小型 synthet 是最接近既有 App 介面的候選，應先評測它；237 MB I-MuPPET 不因數值轉換成功就成為即時追焦方案。這是交付缺口，不是功能完成。本輪增加可重現的評分工具，沒有把工具的合成單元測試算成鳥眼準確率。

本機再次計算 synthet checkpoint SHA-256，仍為 `ec9e4b80a93eb6e2b21633e2ff2df30c49faa1eb7919dd24345c7dc295b2d1be`。既有 FLOAT32 Core ML 合成 parity 已通過，但不是辨識或真機速度驗收。[既有實測](bird-eye-feasibility.md)、[研究 run 39704478800](https://github.com/m2912kenny3643/camera/actions/runs/39704478800)。

## 權利證據：已知事實與未決問題分開

- [synthet 模型卡](https://huggingface.co/synthet/eye-pose-v0/raw/6e7bd361ba84b17d81f0fb4315a44a868df5b692/README.md) 宣告 MIT；既有完整 checkpoint 靜態紀錄顯示 AGPL-3.0 metadata。此輪可讀的最新卡片內容仍相同，沒有找到針對該 checkpoint 的新增授權澄清。固定 revision `6e7bd361ba84b17d81f0fb4315a44a868df5b692` 保持不變；不能以 MIT 卡片抹去 AGPL 通知。
- [Ultralytics 官方說明](https://www.ultralytics.com/license#choosing-your-license) 有完整開源 AGPL 路線。使用者已接受 App AGPL 與完整來源，因此「必須先購買企業授權」不是目前既定阻擋。MIT／AGPL metadata 差異也不等於已證明禁止使用；需記錄各自來源、範圍與適用通知。
- [CUB 官方條件](https://www.vision.caltech.edu/datasets/cub_200_2011/#download) 限制來源圖片的研究／教育用途，且發布者不擁有全部圖片著作權。它沒有在該頁直接裁定所有訓練權重的再散布條件。因此這是**權重來源條件未釐清**，不能改寫成「法律已確定禁止權重散布」。在本計畫要求證據通過後才打包的條件下，尚不能把 `redistribution_verified` 改成 true。
- 沒有向作者寄信或提交授權詢問。若需要第三方澄清，需另有對外聯絡授權；目前不藉此假設使用者已允許代寄。

## 新候選查核

| 候選 | 新確認的事實 | 決定 |
|---|---|---|
| synthet/eye-pose-v0 | 約 5.65 MB，真正左右眼／喙／頭頂點；既有 Core ML adapter 與合成 parity | 優先完成獨立真實圖與手機測試；目前未解除散布閘門 |
| Airdreamer/SuperPicky-models | 新找到現成 Core ML 轉換；眼點模型 `KeypointDetector.weight.bin` 98,676,800 bytes，SHA-256 `0ce77aefef957af92ffbc58e23897f7b6127ac79ab1d23f8a0395db9f296d82c` 是卡片宣告，未下載核驗。來源 ResNet50、CUB 左眼／右眼／喙，卡片明示沿用各上游條件；只提供 compiled model 權重 blob，不是完整可直接套用本 App 的模型契約 | 可減少某些轉換工程，但沒有比 synthet 更清楚的權重／資料證據，也沒有本 App 真機效能；不直接換包 |
| rtmlib Animal / RTMPose / ViTPose | README 高階介面列 bird；實際 animal solution 使用 APT36K ViTPose，模型表的動物 pose 訓練分類是四足動物。COCO detector 能框 bird 不證明 pose 受過鳥眼訓練 | 不把通用動物／鳥身偵測冒充鳥眼 |
| I-MuPPET | 權重發布物有 CC BY 4.0，完整 ONNX parity 通過；Mac CPU 約 1.7–1.8 秒／張，僅鴿子來源證據 | 保留研究對照，不當即時通用鳥眼完成品 |

來源：[SuperPicky Core ML 作者卡片](https://huggingface.co/Airdreamer/SuperPicky-models)、[rtmlib 原始 animal solution](https://github.com/Tau-J/rtmlib/blob/main/rtmlib/tools/solution/animal.py)、[rtmlib 模型表](https://github.com/Tau-J/rtmlib#animal)、[I-MuPPET 原始權重 deposit](https://zenodo.org/records/7037589)、[實際 ONNX 研究結果](imuppet-onnx-result-0.5.json)。SuperPicky 卡片的 Apple Neural Engine 描述是作者宣告，不當成本 App 或 iPhone 的量測。

## 為什麼目前不能把網路抓到 100 張當獨立測試

1. synthet 作者卡片說其 CUB 切分約 10k train／1.7k val，並非已證明沿用 CUB 官方 train/test。沒有實際訓練影像清單，隨便取 CUB「官方 test」100 張不能宣稱訓練外獨立；CUB 官方另提醒 ImageNet 預訓練有重疊風險。[模型訓練說明](https://huggingface.co/synthet/eye-pose-v0#training)、[CUB 原始提醒](https://www.vision.caltech.edu/datasets/cub_200_2011/)。
2. [BirdGaze Dryad](https://datadryad.org/dataset/doi:10.5061/dryad.bk3j9kdpb) 的已發布物約 691 MB，內容是來源資料的額外標註，混有 CUB、Animal Kingdom、NABirds、Birdsnap、eBird、3D-POP。Dryad CC0 不自動重授權各來源照片，也不自動排除 CUB 訓練重疊；相關 Zenodo 程式 archive 先前已檢查沒有所需預訓練權重。
3. [Animal Kingdom 原始說明](https://github.com/sutdcv/Animal-Kingdom/blob/master/Animal_Kingdom/pose_estimation/README_pose_estimation.md#dataset-and-code) 的下載入口是表單，具有真正眼／頭點與可見性欄位；不是本機已備妥的 100 張可驗收圖片。不得把取得註解等同取得可用影像。

可執行下一步是：取來源及用途有明確證據、確認未用於該模型訓練的照片，保存每張檔案 hash、來源及人工標註；另有遮眼、多鳥與遠距組。最乾淨的獨立性證據是模型固定版本發布後自行拍攝的鳥照片，但本輪沒有這批素材，也沒有連接 iPhone。這是工程建議，不是已完成的資料蒐集。

## 新增可重現評分工具

`scripts/bird_eval_metrics.py` 只讀外部實際標註與模型推論 JSON，不下載、不訓練、不生成測試照片。執行：

```sh
python scripts/bird_eval_metrics.py actual-bird-evaluation.json --output build/bird-evaluation.json
python -m unittest discover -s scripts -p test_bird_eval_metrics.py -v
```

輸入根層需有實際模型 SHA-256、獨立性及圖片用途證據、images。每張圖具有唯一圖片 SHA-256、`real_image: true`、人工標註來源、真值鳥身／頭框與左右眼可見性，以及模型預測。詳細欄位由腳本 docstring 固定。評分工具讀取這些外部證據宣告，**不替代人工來源審查，也不證實 hash 已對實際檔案重算**。

- 鳥身框以 IoU≥0.5 的最高重疊優先一對一配對，保留左右眼語意。它是明確的 greedy 評分協議，不聲稱是最優指派；重複鳥候選及未配對眼點均計入假陽性。
- 預設眼 confidence≥0.5，位置正確門檻為真值頭框對角線的 0.1。這是新增的**評測慣例**，需與真實畫面可用性一起檢視；同時報 0.025／0.05／0.1／0.2 的可見眼召回曲線與平均正規化誤差，避免只報單一較寬門檻。
- 眼 precision＝正確眼預測／全部眼預測；recall＝正確眼預測／全部可見真值眼。沒有任何預測時 precision 為 null，不能假設 100%。
- 不可見眼誤報率＝被預測到的不可見真值眼槽／全部不可見真值眼槽；沒有不可見眼時不能宣稱通過 1% 門檻。未配對鳥的眼另計假陽性，不拿未知可見性當成不可見。
- 頭部降級只計眼點未達門檻、來源為實際關鍵點且與真值頭框 IoU≥0.5 的案例，拒把鳥身推估頭框計為正確降級。
- 少於 100 張有鳥真值的獨立照片、資料證據缺失、可見／不可見眼覆蓋缺失、precision<95% 或不可見眼誤報率>1% 都不通過 accuracy 門檻。空白負例可另加，不能替代 100 張鳥照片。每張影像的 `distant` 布林標記提供遠距組；每個鳥真值的非空 `species` 提供物種標記；遮眼與多鳥數量分別由真值可見性及鳥數推導。至少需有一張遠距、一張遮眼、一張多鳥及兩種鳥種，報告保存這些實際數量；此最低覆蓋檢查不取代人工分層審查。即使數字達標，`release_qualified` 也固定 false：權重來源審查與 iPhone≥10Hz／P95≤150ms 是獨立閘門。

本輪 **10 個合成評分單元測試通過**，涵蓋正確眼、遮眼假點、重複候選、完全漏檢、錯誤定位同時計入假點與漏檢、重複 hash／NaN／未知可見性、真假頭部降級、100 張合成圖不得合格、空白照片不替代情境覆蓋，以及數字通過也不得授權散布。它們驗證的是評分公式，不是模型。

## 未完成的驗收

真實獨立圖片數仍為 **0**；沒有實際鳥眼 precision／recall／誤報率／手機 P95 可報。模型授權證據及真機驗收未閉合，保持 `docs/bird-release.json` 的未通過狀態。此輪不散布模型，不發布宣稱有可用鳥眼的無模型 IPA。

## 發布閘門：具體檔案與數值必須可重現

`scripts/check_bird_release.py` 原先僅驗證 report 路徑字串存在於 manifest，未確認該檔案實際存在或內容。已修正為以下契約；**目前真實 manifest 仍為未通過，沒有新增虛構合格報告**。

- manifest 的 `accuracy_report`、`accuracy_input`、`device_report` 必須是 repo 內的相對檔案路徑，並分別有 `<欄位名稱>_sha256`。路徑不存在、逃逸 repo 或內容 hash 改變皆失敗。accuracy input 是評分工具讀取的實際人工標註／推論 JSON；accuracy report 的 `input_sha256` 必須相同。
- 兩份 report 的 `model_sha256` 必須等於 manifest 的原始 checkpoint hash，`converted_package_sha256` 必須等於實際 package 的內容 hash。accuracy input 的模型 hash 也必須相同，避免舊報告套用到另一個模型。
- accuracy report 保留評分工具產物，另加 `converted_package_sha256` 與 `review`。`review.reviewed_by`／`reviewed_at` 是非空文字；`real_images_verified`、`independence_verified`、`image_rights_verified`、`coverage_verified` 必須為 true。程式會從 hash 固定的 input 重算圖片數、可見／不可見眼數、precision／recall、錯誤點及誤報率，要求報告一致；不接受只寫 `accuracy_thresholds_met: true`。頭對角線容差不得比 0.1 更寬。數值合格仍不等同真實來源已經人工審查。
- device report 也有具名、具日期的 `review`，且 `real_device: true`、`platform: "iOS"`、`device_model` 以 iPhone 開頭、非空 `os_version`，明確排除模擬器與 Mac 速度。`latency_scope` 固定為 `camera_frame_to_focus_result`，不可只交模型算子執行時間。
- device trace 使用同一單調時鐘秒數：`measurement_start`、`measurement_end`，以及 `samples` 每筆的 `frame_timestamp`、`completed_timestamp`。必須至少 10 秒、100 筆、影像時間嚴格遞增，且影像與完成時間都在窗口內。首筆及末筆完成結果距離測量窗口兩端不得超過 250ms，任兩個相鄰完成結果的間隔也不得超過 250ms；這是與 App 結果時效一致的持續覆蓋條件，防止第一秒集中跑完 100 次、接著閒置卻冒稱持續 10 秒。由 trace 重算 `sustained_seconds`、`measured_hz`、`p95_latency_ms`（nearest-rank P95），要求宣告數值一致，最後驗證 ≥10Hz 與 P95≤150ms。250ms 的覆蓋限制不取代速度與 P95 門檻。不能只放數字或報告檔名。
- 人工 reviewed 欄位與 hash 是可稽核的證據鏈，不是加密簽名，也不自動證明照片權利／標註真實性。未填寫或未通過時保持 fail closed；不要求 accuracy-only 工具的 `release_qualified` 為 true，因它依設計永遠 false，散布決策在此閘門另行完成。

發布閘門的合成單元測試只測上述檢查行為，包括舊式只有 path 字串不得通過。測試內的假模型、假權利聲明與假 iPhone trace 不會寫入實際發布 manifest，也不是鳥眼效能驗收。
