# R6 Camera

原生 Swift iPhone 相機，參考 EOS R6 Mark III 的拍攝資訊與 Q／MENU 操作。
目標裝置：iPhone 17 標準版、iOS 27。這是獨立專案，並非 Canon 官方 App。

## GitHub 編成 IPA

1. Push 到 `main`，或在 Actions → **Build iPhone IPA** → **Run workflow**。
2. 工作流程下載 Apple 主體偵測模型、產生 Xcode 專案、執行測試並編譯。
3. 成功後下載 **R6Camera-unsigned-IPA** artifact，解壓取得 `.ipa`。
4. 使用相容的側載工具重新簽署後安裝；下載的 IPA 不能直接永久安裝。
   免費帳號的簽署有效期與 App 數量限制依 Apple 和側載工具規定。

CI 使用 `xcode-27` runner 和 `/Applications/Xcode_27.0.app`。
若 GitHub 尚未對帳號提供此 runner，需選用含相同 SDK 的 macOS runner。
最低部署版本 18.0，使用公開 API，目標真機為 iOS 27。
本專案不含登入、後端或上傳影像功能；所有主體推論在手機執行。

## 0.2 改版操作

- 固定橫向：相機鍵在上緣、Dynamic Island 左側、USB-C 右側；Q、MENU 與回放同方向。
- 實體相機鍵：單張在完全按下時拍照；連拍按住開始、放開停止。不使用輕按或側鍵滑動縮放。
- 螢幕右側倍率按鈕展開部分圓弧轉盤；上下拖動、捏合可調倍率。轉盤刻度與文字共用同一圓心。
- 觸控前最多一個白色候選框，只辨識，不自動驅動鏡頭追焦。沒有候選不畫框。
- 點中主體後，一個藍框持續追焦，使用眼睛→觀測到的頭部區域→身體。畫框與鏡頭使用同一目標。
- 點選空白處留下固定藍色正方形，只進行一次對焦。新主體出現不會自動把它改成追焦。
- 主體短暫遮擋先保持距離；超過寬限不跳鎖旁人，清除藍框並回到白框待選。右側 × 可解除觸控指定。
- 主畫面各設定可點選。Q 保留取景，二級選單依手冊採橫列、直列或白平衡圖示盤。
- MENU 使用圖示分頁與雙欄設定。C1–C3 在「自訂／我的選單」載入與儲存。
- MF：選單調焦，取景放大按鈕提供 3× 顯示及邊緣輔助。MF 不顯示自動追焦框。
- 照片先存 App，再寫入相簿；回放可翻頁、放大、分享處理後照片／RAW、確認後刪除 App 內副本。

### 尚未完成的必要項目

鳥眼／鳥頭模型尚未建立可合法散布且經手機驗證的部署路徑；目前鳥類只有身體偵測，**不代表鳥眼需求已完成**。模型候選、授權與部署缺口見 [研究筆記](docs/research/bird-eye-feasibility.md)。人物支援臉／眼；狗貓頭部區域來自可靠觀測關鍵點的包圍範圍，並非專用頭部偵測模型。

UI 使用程式繪製，圖示未能從手冊建立完整定義的部分使用明確文字，不使用生成圖的畸形動物圖案。AF 區域固定全畫面辨識／觸控指定；測光採系統控制，沒有假的 Canon 測光模式切換。轉盤等效焦段由實際視角推估，前置 ≈ 記號，不寫死成示意圖數值。

## 能力與誠實顯示

- P／自動：系統 AE；Tv：固定快門、ISO 回授調整；M：固定快門與 ISO；
  Fv：快門與 ISO 可各自設為自動。鏡頭限制會夾住要求值，拍攝畫面顯示實際值。
- iPhone 17 沒有可變光圈；Av 顯示為不可調，第一版不模擬光圈或景深。
- RAW 僅在目前鏡頭配置實際支援時可選；不承諾標準版 ProRAW。
- 藍框表示觸控指定位置或追蹤目標，不保證已量測眼部銳利度。白框不觸發追焦。
- 主體身分以類別與幾何位置關聯，不是人臉辨識。交叉、快速移動、長時間遮擋可能失敗。
  不會在目標遺失後聲稱已重新辨識同一個人。人物/動物識別品質取決於模型、光線與距離。
- 相片風格是獨立調校的近似效果，並非 Canon 色彩演算法；RAW 保持未套風格。
- 右側螢幕轉盤為自訂重現；沒有註冊側鍵縮放浮層。其餘介面參考手冊並固定橫向。
- 不含錄影、進階合成、包圍對焦、預拍、堆疊長曝或 Canon 配件支援。

## 開發與驗證

Windows 可修改來源；完整 Swift／iOS 編譯需由 macOS Xcode 或 GitHub Actions 執行。
在 macOS：

```sh
brew install xcodegen
python3 scripts/prepare_model.py
xcodegen generate
xcodebuild test -project R6Camera.xcodeproj -scheme R6Camera \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest' CODE_SIGNING_ALLOWED=NO
```

Python 包裝測試：`python scripts/test_packaging.py`。

Swift 測試覆蓋主體鎖定不跳旁人、遮擋恢復、眼睛降級、類別篩選、
交錯歧義、白框無 AF 指令、點選空白僅一次 AF、眼頭身體降級、轉盤圓心與座標轉換及 C1–C3 保存，可在 macOS 以 `swift test` 執行。
CI 先執行核心測試、驗證裝置版 archive 與 IPA 結構，再執行模擬器介面測試。
UI 截圖另存為 `UI-screenshots` artifact；介面測試失敗時整個 run 仍會標示失敗。

真機驗收清單見 [docs/DEVICE-TESTS.md](docs/DEVICE-TESTS.md)。
建置通過不代表硬體按鍵、追焦與成像已通過真機驗證。

## 技術來源

- [Apple Camera Control](https://developer.apple.com/documentation/avfoundation/enhancing-your-app-experience-with-the-camera-control)
- [Apple 拍攝硬體按鍵](https://developer.apple.com/videos/play/wwdc2025/253/)
- [Vision 動物姿態與眼睛](https://developer.apple.com/videos/play/wwdc2023/10045/)
- [Apple 主體模型](https://developer.apple.com/machine-learning/models/)
- [手動曝光與畫質優先注意事項](https://developer.apple.com/videos/play/wwdc2026/8018/?time=827)
- [GitHub runner](https://github.com/actions/runner-images/blob/main/images/macos/xcode-27-arm64-Readme.md)

手冊 PDF 僅在本機供研究，未隨專案散布。
