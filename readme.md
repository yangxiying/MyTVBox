
## 注意事项

1. **iOS无法执行JAR爬虫**: TVBox的Type=3(Spider)源在iOS上不可用，仅支持Type=0(XPath)和Type=1(API)类型的站点
2. **HTTP明文传输**: 猫爪接口可能使用HTTP，需要在Info.plist中配置ATS例外
3. **后台播放**: 必须在Capabilities中开启Background Modes -> Audio, AirPlay, and Picture in Picture
4. **自签名限制**: 通过AltStore侧载的应用每7天需要重新签名（免费开发者账号）
5. **网络认证**: 接口URL中的 `user:pass@host` 格式需要在URLSession中正确处理HTTP Basic Auth
