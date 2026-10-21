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

## 操作

- 實體相機鍵：單張模式放開拍照；連拍模式按住拍攝、放開停止。
- Camera Control：使用 Apple 原生縮放控制。畫面捏合／倍率按鈕亦可縮放。
- 半按對焦：公開 API 尚未驗證支援，使用 AF-ON 或點選主體對焦。
- 點選主體：鎖定目標。遮擋時等待，超過寬限後顯示目標遺失，點選重新鎖定。
- 人物與狗／貓：眼睛偵測，可選左／右眼優先。鳥、馬及車輛使用主體框。
- 主體識別：人物、狗、貓、鳥、馬、汽車、機車、飛機、火車。
- Q：快速設定曝光、AF、主體、眼睛、風格、白平衡、畫質與驅動。
- MENU：分頁設定；INFO：資訊顯示；C1–C3：點選載入、長按儲存。
- MF：選單調整焦距，取景放大按鈕提供 3× 顯示，另有邊緣輔助。
- 照片先存 App，接著寫入相簿。回放可分享 JPEG／HEIF 及對應 DNG。

## 能力與誠實顯示

- P／自動：系統 AE；Tv：固定快門、ISO 回授調整；M：固定快門與 ISO；
  Fv：快門與 ISO 可各自設為自動。鏡頭限制會夾住要求值，拍攝畫面顯示實際值。
- iPhone 17 沒有可變光圈；Av 顯示為不可調，第一版不模擬光圈或景深。
- RAW 僅在目前鏡頭配置實際支援時可選；不承諾標準版 ProRAW。
- 綠框僅表示單次鏡頭 AF 完成，不代表已量測眼部銳利度；追焦框與鏡頭 AF 分開處理。
- 主體身分以類別與幾何位置關聯，不是人臉辨識。交叉、快速移動、長時間遮擋可能失敗。
  不會在目標遺失後聲稱已重新辨識同一個人。人物/動物識別品質取決於模型、光線與距離。
- 相片風格是獨立調校的近似效果，並非 Canon 色彩演算法；RAW 保持未套風格。
- 原生 Camera Control 浮層為 iOS 樣式，其餘介面參考手冊並適配手機橫直向。
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
交錯歧義、橫直向座標轉換與 C1–C3 保存，可在 macOS 以 `swift test` 執行。
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
