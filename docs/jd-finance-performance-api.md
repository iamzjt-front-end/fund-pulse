# 京东金融基金历史收益接口链路

> 维护状态：京东金融生产 H5 的内部接口资料，仅用于 `fund-pulse` 的个人数据同步。最后验证：2026-07-15。

这些接口来自京东金融基金持仓页跳转到“资产收益”页后的真实生产链路，但不是对外承诺的开放 API。路径、字段和前端资源哈希都可能变化；接入时必须保留结构校验、登录失效提示和失败不覆盖本地数据的保护。

本文只记录脱敏后的协议结构。Cookie、账号标识、设备标识和真实资产金额不得写入源码、测试、日志或文档。

## 官方页面与证据

- 基金持仓入口：<https://roma.jd.com/fund/hold/list/pc/>
- 持仓页生产脚本（验证时版本）：<https://roma.jd.com/fund/hold/js/main_3b4cc5cf3e.js>
- `fundHoldGroup` 返回的收益明细落地页：<https://mix.jd.com/mix/asset-mark/home/?conditionType=fund>
- 收益页生产脚本（验证时版本）：<https://mix.jd.com/mix/asset-mark/assets/index-legacy-d2dbc81b.js>

持仓页脚本读取 `headAssetsData.incomeDetailUrlData.jumpData`，登录后 `jumpUrl` 最终落到上述 `asset-mark` 页面。收益页脚本直接包含本文 B-G 的接口路径和请求字段。带哈希的脚本 URL 会随发布轮换，失效时从稳定页面 HTML 重新查找当前资源文件。

## 通用请求协议

B-G 使用同一个网关前缀：

```http
POST https://ms.jr.jd.com/gw2/generic/cfGateway/h5/m/{method}
Content-Type: application/x-www-form-urlencoded;charset=UTF-8
Origin: https://mix.jd.com
Referer: https://mix.jd.com/mix/asset-mark/home/?conditionType=fund
Cookie: <当前京东登录态，仅在内存中使用>
```

表单体只有一个字段，值是 JSON：

```text
reqData=<percent-encoded JSON>
```

通用双层响应：

```json
{
  "success": true,
  "resultCode": 0,
  "resultMsg": "success",
  "resultData": {
    "code": "0000",
    "success": true,
    "message": "success",
    "data": {}
  }
}
```

- 外层成功条件：`resultCode == 0`，并且 `success` 不是 `false`。
- 内层成功条件：`code == "0000"`，并且 `success` 不是 `false`。
- 未登录实测可在外层返回 `resultCode == 3`；登录过期也可能从内层 `code/message` 返回。
- 解析器必须同时检查两层，不能只看 HTTP 200。

## A. 基金持仓与收益摘要：`fundHoldGroup`

### 请求

当前 app 已验证路径：

```http
GET https://ms.jr.jd.com/gw/generic/base/h5/m/fundHoldGroup?reqData=<JSON>
```

当前持仓页脚本也出现新版路径：

```http
GET https://ms.jr.jd.com/gw/generic/base/newna/m/fundHoldGroup?reqData=<JSON>
```

`reqData`：

```json
{
  "clientVersion": "",
  "clientType": "android",
  "apiVersion": 1,
  "appChannel": "fund_jjcc",
  "sortKey": "1",
  "sortDirection": "DESC",
  "extParams": {
    "channelCode": "outside"
  }
}
```

### 关键响应字段

```text
resultData.resultData.headAssetsData.totalAssets
resultData.resultData.headAssetsData.yesterdayIncome
resultData.resultData.headAssetsData.todayIncome
resultData.resultData.headAssetsData.holdIncome
resultData.resultData.headAssetsData.totalIncome
resultData.resultData.headAssetsData.incomeDetailUrlData.jumpData
resultData.resultData.headAssetsData.incomeDetailUrlData.trackData
```

五个金额字段不是裸数字，而是用于展示的对象，内部常见 `title/subTitle` 及文本叶子。`jumpData` 常见字段：

```text
jumpType
jumpShare
schemeUrl
xviewType
jumpUrl
```

这个接口只提供持仓总览和收益摘要，不能替代逐日历史收益。

证据：基金持仓入口及其生产脚本；`jumpData` 的实测目标是稳定的 `asset-mark` 页面。

## B. 收益概览：`getIncomeTrailPart1`

### 请求

```http
POST /gw2/generic/cfGateway/h5/m/getIncomeTrailPart1
```

```json
{
  "risk_type": "",
  "rf_type": "fund",
  "rate_type": "most",
  "incomeDateType": "currYear",
  "indexCode": "000300"
}
```

### 响应 `resultData.data`

```text
incomeAmount: number
rateFlag: string
yesterdayInome: number
totalIncomeFlag: string
incomeRate: number
```

注意：生产字段确实拼作 `yesterdayInome`，不是 `yesterdayIncome`。

证据：收益页生产脚本中的 `getIncomeTrailPart1` 请求方法和消费字段。

## C. 收益走势：`getIncomeTrailPart2`

### 请求

```http
POST /gw2/generic/cfGateway/h5/m/getIncomeTrailPart2
```

请求字段与 B 相同。`incomeDateType` 的前端枚举：

```text
currYear   本年，1 月 1 日至当前
singleYear 近一年
sixMonth   近六个月
threeMonth 近三个月
oneMonth   近一个月
```

### 响应 `resultData.data`

```text
rateFlag: string
totalIncomeFlag: string
myIncomeRates: array
indexRate: array
hs300Rate: array
```

三个序列的日记录常见字段：

```text
incomeDate
incomeAmount
index
incomeRate
weekNumber
currentWeek
crossMonth
```

`myIncomeRates[]` 还会出现 `beatIndexRate`。接口按所选区间一次返回，没有看到分页字段。

证据：收益页生产脚本中的 `getIncomeTrailPart2`、区间枚举和曲线数据映射。

## D. 维度收益明细：`getIncomeDateDetail`

### 日维度请求

```http
POST /gw2/generic/cfGateway/h5/m/getIncomeDateDetail
```

```json
{
  "risk_type": "",
  "rf_type": "fund",
  "rate_type": "most",
  "incomeDateType": "singleYear",
  "year": 2026,
  "month": 7,
  "incomeDateDimension": "day",
  "rateFlag": "1"
}
```

### 累计收益请求

```json
{
  "risk_type": "",
  "rf_type": "fund",
  "rate_type": "most",
  "incomeDateDimension": "total_income",
  "rateFlag": "1",
  "incomeDateType": "currYear",
  "totalIncomeDateDimension": "currYear"
}
```

前端支持的 `incomeDateDimension`：

```text
day
week
month
year
total_income
```

### 响应 `resultData.data`

日维度：

```text
incomeFlag
rateFlag
incomeRateVoMap.<YYYY-MM-DD>.incomeAmount
incomeRateVoMap.<YYYY-MM-DD>.incomeDate
incomeRateVoMap.<YYYY-MM-DD>.incomeRate
incomeRateVoMap.<YYYY-MM-DD>.index
incomeRateVoMap.<YYYY-MM-DD>.weekNumber
incomeRateVoMap.<YYYY-MM-DD>.currentWeek
incomeRateVoMap.<YYYY-MM-DD>.crossMonth
```

周维度记录还会出现：

```text
startDate
endDate
startDateStr
endDateStr
netInflowSum
```

累计维度返回 `totalIncomeList[]`，日记录以 `incomeAmount` 表示对应日期的累计值，并带日期和辅助字段。

证据：收益页生产脚本中的维度切换、`getIncomeDateDetail` 请求和返回值映射。

## E. 任意日期区间日收益：`getIncomeDateDetailRange`

这是 `fund-pulse` 同步历史收益的主接口。

### 请求

```http
POST /gw2/generic/cfGateway/h5/m/getIncomeDateDetailRange
```

```json
{
  "risk_type": "",
  "rf_type": "fund",
  "rateType": "most",
  "rateFlag": "1",
  "incomeDateDimension": "day",
  "dateFrom": "2026-01-01",
  "dateTo": "2026-07-14"
}
```

注意这里是 `rateType`，而 B-D 使用 `rate_type`。字段名不能互换。

### 响应 `resultData.data`

```text
incomeFlag
rateFlag
incomeRateVoMap
```

`incomeRateVoMap` 以 `YYYY-MM-DD` 为 key，每条记录与 D 的日维度相同。`dateFrom/dateTo` 均为闭区间，没有看到分页字段。

生产环境验证过从 `2020-01-01` 到当前日期的一次请求，能返回完整日历日序列；其中持有前、非交易日或尚未结算日期可能是 0 值。服务端没有公开最大跨度，因此正式实现按自然年切分，并保证每段最多 366 个日历日。

`fund-pulse` 的同步约定：

- 未指定 `dateTo` 时使用上海时区“昨天”，避免把当天暂估/未结算值固化。
- 每段成功后再参与合并；任一段失败时不返回伪完整结果。
- 同日期若是京东旧记录或本地估值，会自动用京东已确认值更新；京东把既有非零记录修正为 0 时也会更新，只有本地不存在对应日期时才跳过 0 值日。若与本地已确认值冲突，会先进入预览并默认保留本地值，只有用户明确打开“以京东为准”才覆盖。接口没有返回的已有日期保留，不因空响应删除历史数据。
- `coveredFrom/coveredThrough` 记录本次成功请求范围，所有段成功后 `isComplete = true`。
- 主模型只保存 `date`、`incomeAmount` 和可选 `incomeRate`；未知或畸形金额字段直接报结构变化，不静默写 0。

证据：收益页生产脚本中的 `getIncomeDateDetailRange`；生产登录态下对多种日期范围的脱敏协议验证。

## F. 单日基金收益拆分：`getIncomeSkuDetail`

### 请求

```http
POST /gw2/generic/cfGateway/h5/m/getIncomeSkuDetail
```

```json
{
  "incomeDateDimension": "day",
  "risk_type": "",
  "rf_type": "fund",
  "year": 2026,
  "month": 7,
  "day": 14,
  "groupField": "item_id",
  "sortType": "DESC"
}
```

前端 `groupField` 候选：`item_id`、`risk_type`、`rf_type`；`sortType` 候选：`ASC`、`DESC`。

### 响应 `resultData.data.incomeInfoVoList[]`

```text
totalIncome
itemName
rfType
riskType
rfTypeName
skuId
jumpDetail.jumpShare
jumpDetail.jumpType
jumpDetail.jumpUrl
jumpDetail.xviewType
```

这里的 `totalIncome` 是所选日期/分组桶的收益金额，不应当解释为该基金生命周期累计收益。没有看到分页字段。

证据：收益页生产脚本中的明细弹层、排序/分组选项及 `getIncomeSkuDetail`。

## G. 旧版组合接口：`getIncomeTrail`

```http
POST /gw2/generic/cfGateway/h5/m/getIncomeTrail
```

这是旧版把概览和走势合在一起的接口。当前收益页优先并行使用 B 的 `getIncomeTrailPart1` 与 C 的 `getIncomeTrailPart2`，旧接口只保留为兼容/回退链路。

新代码不应以 G 作为主数据源：拆分接口的字段职责更清楚，E 又能按明确日期范围拉取逐日历史。

证据：收益页生产脚本中的新旧请求分支。

## 接入边界与故障策略

- 只在用户主动登录并发起同步时读取会话 Cookie；仅放在内存请求头中。
- 请求只转发根域 `.jd.com`、路径 `/` 下的 `pt_key`、`pt_pin`、`pin`、`pwdt_id`、`thor`、`wskey`；支付域、京东子域和跟踪 Cookie 不进入接口请求，同名重复项只取当前会话中优先出现的一项。
- 不记录 Cookie、请求完整 headers、账号唯一 ID 或原始金融响应。
- 账号归属仅保存不可逆 SHA-256 指纹，并固定按 `pt_pin > pin > pwdt_id` 取身份字段，不受 Cookie 排列顺序影响。
- 持仓同步与历史收益同步共用账号锚点：请求前与预览写入前都会核对，无法确认账号或与任一已有来源不一致时拒绝抓取或落盘。
- HTTP 200 不代表业务成功；必须验证外层与内层状态。
- 登录失效统一映射成“需要重新登录”，不要当成空收益历史。
- 字段缺失、日期 key 与 `incomeDate` 不一致、金额不可解析时视为协议变化。
- 网络、登录、结构或取消错误都不能清空已有本地收益数据；损坏或来自未来 schema 的历史文件也会被锁定，禁止自动记录和导出覆盖，直到用户明确恢复。
- 任务取消应抛出取消错误，不包装成普通网络失败。
- 这些内部接口可能随京东发布变化；出现结构错误时，先从稳定页面重新定位当前脚本，再核对端点和字段。
