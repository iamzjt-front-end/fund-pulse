# 养基宝小程序接口链路

> 维护状态：逆向资料，仅用于评估和内部接入设计。最后验证：2026-06-27。

本文记录养基宝微信小程序从基金列表到基金详情、关联板块和板块基金的接口链路。当前 `fund-pulse` 正式行情源仍以东方财富 / 天天基金为主；养基宝接口如需接入，必须先评估稳定性、登录态、频率限制和合规风险。

## 基本信息

- 小程序 AppId：`wx8962f01176512bd4`
- 小程序主 API：`https://wxapp-api.yangjibao.com`
- 浏览器插件 API：`http://browser-plug-api.yangjibao.com`
- 已验证样例基金：`024418`
- 样例养基宝内部 ID：`28516`
- 样例名称：`华夏上证科创板半导体材料设备主题ETF联接C`

`fund_id` 是养基宝内部 ID，不是基金代码。不要把基金代码直接放进 `fund_id` 字段；例如 `fund_id: "024418"` 会被服务端当成内部 ID `24418`，返回另一个基金。

## 请求签名

小程序接口统一带以下请求头：

```text
Request-Time: <unix seconds>
Content-Type: application/json; charset=utf-8
Authorization: pcwxapp:<token>
Request-Sign: <md5>
```

Mac / Windows / 微信开发者工具使用 `pcwxapp:` 前缀，移动端使用 `mwxapp:` 前缀。公开接口可以使用空 token，即 `Authorization: pcwxapp:`。

签名规则：

```text
md5(baseUrl + pathWithoutQuery + authorization + key + requestTime)
```

```text
baseUrl = https://wxapp-api.yangjibao.com
key = XywDEscljKUiusjqjjyOheNKdp8mBE3S
pathWithoutQuery = 请求路径，不含 query string
```

Python 示例：

```python
import hashlib
import math
import time

BASE_URL = "https://wxapp-api.yangjibao.com"
KEY = "XywDEscljKUiusjqjjyOheNKdp8mBE3S"

def yjb_headers(path: str, token: str = "") -> dict[str, str]:
    auth = f"pcwxapp:{token}"
    request_time = str(math.ceil(time.time()))
    path_without_query = path.split("?", 1)[0]
    request_sign = hashlib.md5(
        f"{BASE_URL}{path_without_query}{auth}{KEY}{request_time}".encode()
    ).hexdigest()
    return {
        "Request-Time": request_time,
        "Content-Type": "application/json; charset=utf-8",
        "Authorization": auth,
        "Request-Sign": request_sign,
    }
```

## 页面链路

### 1. 持有列表页

页面：`pages/index/index`

实际链路：

1. 获取持有基金静态列表。
2. 从静态列表提取 `fund_id` 和 `user_data_source`。
3. 用批量行情接口补齐净值、估值、关联板块等动态字段。
4. 点击基金，跳转到详情页并传 `fund_id`。

接口：

```http
GET /position/v1/static/fund-accounts/funds
GET /position/v1/static/fund-accounts/{account_id}/funds
```

关键字段：

```text
data.list[].fund_id
data.list[].code
data.list[].user_data_source
data.list[].hold_share
data.list[].hold_cost
data.page_limit
```

批量补动态行情：

```http
POST /market/v1/fund/batch
POST /market/v1/fund/batch/paginated
```

请求体：

```json
{
  "funds": [
    { "fund_id": 28516, "data_source": 1 }
  ]
}
```

小程序逻辑：列表数量超过 `page_limit` 时按块调用 `/market/v1/fund/batch/paginated`，否则调用 `/market/v1/fund/batch`。

批量接口关键响应：

```json
{
  "fund_id": 28516,
  "code": "024418",
  "short_name": "华夏上证科创板半导体材料设备主题ETF联接C",
  "category": 3,
  "market_type": "ch",
  "data_source": "1",
  "nv_info": {
    "dwjz": "2.8495",
    "rzzl": "3.19",
    "jzrq": "2026-06-26",
    "gsz": "2.8495",
    "gszzl": "3.19",
    "true_valuation_date": "2026-06-26",
    "source": "1"
  },
  "sector_info": {
    "name": "科创半导材料",
    "ratio": 3.42,
    "sector_id": null,
    "index_code": "950125.CSI"
  },
  "fund_sector_name": "半导体材料设备"
}
```

列表展示的“关联板块”来自：

```text
sector_info.name
sector_info.ratio
sector_info.index_code
fund_sector_name
```

### 2. 自选列表页

页面：`pages/options/options`

接口：

```http
GET /fund_optional
GET /group_funds?group_id={group_id}
```

关键字段：

```text
data[].fund_id
data[].code
data[].data_source
data[].nv_info
data[].sector_info.name
data[].sector_info.ratio
```

自选列表的返回已经包含 `sector_info`。它不走持有列表的静态列表 + 批量补全流程。

### 3. 搜索页

页面：`pages/search/search`

接口：

```http
GET /search?kw={keyword}&scene={scene}
GET /search_info
DELETE /remove_search_history
```

常见 `scene`：

```text
fund_hold
add_fund_optional
fund_optional_manage
```

搜索结果点击详情时使用：

```text
data.list[].id -> fund_id
data.list[].code -> 基金代码
data.list[].short_name -> 展示名称
```

限制：`/search` 需要登录 token。空 token 会返回 `401`。如果只有基金代码且没有登录态，无法稳定通过搜索接口拿到养基宝内部 `fund_id`。

可用但不完整的公开反查来源：

```http
GET /fund_up_ranking_list
GET /fund_hold_ranking?page=1&per_page=100
```

这两个榜单接口免登录，返回 `fund_id`、`code`、`name`，但只能覆盖榜单内基金，不能当完整搜索索引。

`024418` 的公开反查样例：

```json
{
  "fund_id": 28516,
  "code": "024418",
  "name": "华夏上证科创板半导体材料设备主题ETF联接C"
}
```

### 4. 只取关联板块的免登录方案

如果 `fund-pulse` 只需要基金关联板块，不需要养基宝账户、自选和收益详情，推荐链路是：

```text
基金代码 code
  -> 本地 code -> yjbFundId 映射表
  -> POST /market/v1/fund/batch
  -> sector_info.name / sector_info.ratio / sector_info.index_code / fund_sector_name
```

运行时只依赖一个接口：

```http
POST /market/v1/fund/batch
```

请求体：

```json
{
  "funds": [
    { "fund_id": 28516, "data_source": 1 }
  ]
}
```

字段取值：

```text
sector_info.name       -> 关联板块名称
sector_info.ratio      -> 关联板块涨跌幅
sector_info.index_code -> 关联指数代码
fund_sector_name       -> 基金主题/行业名
```

`code -> yjbFundId` 不建议在用户交互时实时搜索，因为 `/search` 需要登录 token。免登录可用的维护方式是：

1. 优先查本地映射表，例如 `024418 -> 28516`。
2. 维护映射表时，用公开榜单 `/fund_up_ranking_list`、`/fund_hold_ranking?page=1&per_page=500` 补热门基金。
3. 榜单没有覆盖时，用 `/market/v1/fund/batch` 对内部 ID 做低频分段扫描，反向取响应里的 `code` 来补表。

已验证低频扫描样例：`28500..28530` 这 31 个 `fund_id` 一次批量请求可以返回对应基金代码，其中：

```text
28515 -> 024417 -> 科创半导材料
28516 -> 024418 -> 科创半导材料
28517 -> 024680 -> 无关联板块
```

这说明 `/market/v1/fund/batch` 既能取板块，也能作为离线维护映射表的公开数据来源。不要在前台按基金代码临时大范围扫描；扫描只适合手动维护、定时低频刷新或调试验证。

## 详情页链路

页面：`pages/fund_page/fund_page`

入口：

```text
/pages/fund_page/fund_page?fund_id={fund_id}
/pages/fund_page/fund_page?account_id={account_id}&fund_id={fund_id}
```

### 1. 详情主体

```http
GET /fund_profit?fund_id={fund_id}&account_id={account_id}
```

空账户时：

```http
GET /fund_profit?fund_id={fund_id}&account_id=0
```

关键字段：

```text
data.code
data.name
data.category
data.market_type
data.data_source
data.sector
data.sector_index
data.nv_info
data.is_hold
data.is_optional
data.hold_accounts
```

限制：该接口需要登录 token。空 token 返回 `401`。

### 2. 详情顶部“关联板块”图

普通基金使用：

```http
GET /market/v1/fund/gz-data?fund_id={fund_id}&source={data_source}&market_type={market_type}
```

样例：

```http
GET /market/v1/fund/gz-data?fund_id=28516&source=1&market_type=ch
```

当接口没有返回基金自身估值分钟线时，会返回 `relation_info_list`：

```json
{
  "day": "2026-06-26",
  "list": null,
  "market_open_time": [["09:30", "11:30"], ["13:00", "15:00"]],
  "relation_info_list": [
    { "type": 4, "id": "28516", "code": "950125.CSI", "name": "科创半导材料" },
    { "type": 2, "id": "12909", "code": "588170", "name": "华夏上证科创板半导体材料设备主题ETF" },
    { "type": 1, "id": "119", "code": "931743", "name": "半导体材料设备" },
    { "type": 3, "id": "474", "code": "1.000001", "name": "上证指数" },
    { "type": 3, "id": "476", "code": "0.399006", "name": "创业板指" },
    { "type": 3, "id": "477", "code": "1.000300", "name": "沪深300" }
  ]
}
```

小程序默认选择第一条 `relation_info_list[0]` 作为当前关联板块。

随后请求关联分钟线：

```http
GET /market/v1/fund/relation-gz-data?type={type}&id={id}
```

样例：

```http
GET /market/v1/fund/relation-gz-data?type=4&id=28516
```

关键响应：

```json
{
  "day": "2026-06-26",
  "type": "4",
  "id": "28516",
  "list": [
    { "time": "09:30:00", "rise": "-0.81" },
    { "time": "09:31:00", "rise": "-0.81" }
  ]
}
```

### 3. 历史净值

```http
GET /fund_history_nav?fund_id={fund_id}&page=1&per_page=10
GET /money_fund_earn_list?fund_id={fund_id}&page=1&per_page=10
```

`money_fund_earn_list` 用于货币基金；普通基金使用 `fund_history_nav`。

### 4. 重仓股票

```http
GET /fund_hold_stock?fund_id={fund_id}&page=1&per_page=10
POST /stock_price_list
```

`fund_hold_stock` 样例字段：

```text
data.list[].code
data.list[].name
data.list[].ratio
data.list[].rate
data.list[].position_change
```

### 5. 板块基金

详情页内预览和“更多板块基金”使用：

```http
GET /sector_relate?sector_id={sector_id}
```

入口页：

```text
/packageA/pages/plate_fund/plate_fund?sector_id={sector_id}
```

限制：`sector_id` 来自 `/fund_profit` 的 `data.sector`，该链路需要登录 token。`/market/v1/fund/batch` 返回的 `sector_info.sector_id` 可能为 `null`，不能稳定替代。

### 6. 数据源切换

详情页查看单只基金数据源：

```http
GET /fund_source_list?fund_id={fund_id}
```

全局切换数据源页面：

```http
POST /fund_gz_source
```

请求体：

```json
{
  "data_source": 1,
  "fund_id": null
}
```

小程序数据源文案：

```text
数据源1：更新频率较快，准确率中等
数据源2：更新频率较慢，准确率较高
数据源3：更新频率最快，准确性中等
```

这些接口需要登录 token。

## 端点总览

| 场景 | 方法 | 路径 | 登录态 | 关键字段 |
| --- | --- | --- | --- | --- |
| 持有静态列表 | GET | `/position/v1/static/fund-accounts/funds` | 需要 | `data.list[].fund_id`, `user_data_source` |
| 指定账户持有列表 | GET | `/position/v1/static/fund-accounts/{account_id}/funds` | 需要 | `data.list[]`, `page_limit` |
| 批量动态行情 | POST | `/market/v1/fund/batch` | 空 token 可用 | `nv_info`, `sector_info`, `fund_sector_name` |
| 分页批量动态行情 | POST | `/market/v1/fund/batch/paginated` | 空 token 可用 | 同上 |
| 自选列表 | GET | `/fund_optional` | 需要 | `fund_id`, `nv_info`, `sector_info` |
| 分组自选列表 | GET | `/group_funds?group_id=` | 需要 | 同上 |
| 搜索基金 | GET | `/search?kw=&scene=` | 需要 | `data.list[].id`, `code`, `short_name` |
| 涨幅榜 | GET | `/fund_up_ranking_list` | 空 token 可用 | `fund_id`, `code`, `name` |
| 持有榜 | GET | `/fund_hold_ranking?page=&per_page=` | 空 token 可用 | `fund_id`, `code`, `name` |
| 详情主体 | GET | `/fund_profit?fund_id=&account_id=` | 需要 | `sector`, `sector_index`, `data_source`, `market_type` |
| 基金估值/关联列表 | GET | `/market/v1/fund/gz-data?fund_id=&source=&market_type=` | 空 token 可用 | `list`, `relation_info_list` |
| 关联分钟线 | GET | `/market/v1/fund/relation-gz-data?type=&id=` | 空 token 可用 | `data.list[].time`, `rise` |
| 历史净值 | GET | `/fund_history_nav?fund_id=&page=&per_page=` | 空 token 可用 | `day`, `unit_net`, `rise_range` |
| 重仓股票 | GET | `/fund_hold_stock?fund_id=&page=&per_page=` | 空 token 可用 | `code`, `name`, `ratio`, `rate` |
| 板块基金 | GET | `/sector_relate?sector_id=` | 需要 | 同板块基金列表 |
| 指数涨幅刷新 | GET | `/index_rate?index_code=` | 需要 | `rate` |
| 数据源列表 | GET | `/fund_source_list?fund_id=` | 需要 | 数据源配置 |
| 保存数据源 | POST | `/fund_gz_source` | 需要 | `data_source` |

## `fund-pulse` 建议接入边界

### 可以作为候选能力

已知 `fund_id` 时，可以用空 token 获取关联板块：

```http
POST /market/v1/fund/batch
```

核心字段：

```text
sector_info.name
sector_info.ratio
sector_info.index_code
fund_sector_name
```

运行时推荐顺序：

1. 本地读取 `code -> yjbFundId`。
2. 调用 `/market/v1/fund/batch`。
3. 如果 `sector_info.name` 非空，展示为养基宝关联板块。
4. 如果本地没有映射或 `sector_info.name` 为空，回退到当前主数据源，不在前台临时扫描养基宝内部 ID。

如果要展示详情页那条关联曲线，可以追加：

```http
GET /market/v1/fund/gz-data?fund_id={fund_id}&source=1&market_type=ch
GET /market/v1/fund/relation-gz-data?type={type}&id={id}
```

### 暂不建议自动依赖

如果只有基金代码，稳定获取 `fund_id` 的 `/search` 需要登录 token。除非用户明确提供合法登录态，否则不要在应用内自动读取或持久化养基宝 token。

可选策略：

1. 维护本地 `code -> yjbFundId` 映射表，只对已验证基金启用。
2. 用公开榜单接口补充热门基金映射，但标记为不完整。
3. 用 `/market/v1/fund/batch` 低频分段扫描内部 ID，离线补齐映射表。
4. 保留东方财富 / 天天基金作为主数据源，养基宝仅作为可关闭的实验性增强。

## 维护流程

每次更新本文档或接入代码时，按下面顺序验证：

1. 更新“最后验证”日期。
2. 用 `024418 -> 28516` 重新验证 `/market/v1/fund/batch` 是否返回 `sector_info.name`。
3. 重新验证 `/market/v1/fund/gz-data` 是否返回 `relation_info_list`。
4. 重新验证 `/market/v1/fund/relation-gz-data?type=4&id=28516` 是否返回分钟线。
5. 重新验证公开榜单或小范围 `/market/v1/fund/batch` 扫描仍能维护 `code -> yjbFundId`。
6. 不提交任何真实 `Authorization` token、用户账户 ID、完整抓包文件或包含个人资产的数据。
7. 如果接口字段变化，优先更新“端点总览”和“`fund-pulse` 建议接入边界”两节。

最小验证脚本。生产代码必须使用可信 CA 校验证书；如果本机代理证书没有导入 Python 证书链，手动验证时可以临时使用 `curl -k`，但不要把跳过证书校验的逻辑带进应用代码。

```bash
python3 - <<'PY' | sh
import hashlib
import json
import math
import time

BASE_URL = "https://wxapp-api.yangjibao.com"
KEY = "XywDEscljKUiusjqjjyOheNKdp8mBE3S"
AUTH = "pcwxapp:"

def signed_curl(path: str, body: dict | None = None):
    ts = str(math.ceil(time.time()))
    sign_path = path.split("?", 1)[0]
    sign = hashlib.md5(f"{BASE_URL}{sign_path}{AUTH}{KEY}{ts}".encode()).hexdigest()
    method_args = ""
    if body is not None:
        payload = json.dumps(body, separators=(",", ":"))
        method_args = f"-X POST --data '{payload}'"
    print(
        "curl -sS -k --max-time 20 "
        f"-H 'Request-Time: {ts}' "
        "-H 'Content-Type: application/json; charset=utf-8' "
        f"-H 'Authorization: {AUTH}' "
        f"-H 'Request-Sign: {sign}' "
        f"{method_args} '{BASE_URL}{path}'"
    )

signed_curl("/market/v1/fund/batch", {
    "funds": [{"fund_id": 28516, "data_source": 1}]
})
signed_curl("/market/v1/fund/gz-data?fund_id=28516&source=1&market_type=ch")
signed_curl("/market/v1/fund/relation-gz-data?type=4&id=28516")
PY
```

## 浏览器插件接口补充

开源项目 [Ye-Yu-Mo/yjb-api](https://github.com/Ye-Yu-Mo/yjb-api) 封装的是养基宝浏览器插件接口，不是微信小程序接口。

基本信息：

```text
baseUrl = http://browser-plug-api.yangjibao.com
key = YxmKSrQR4uoJ5lOoWIhcbd7SlUEh9OOc
sign = md5(pathWithoutQuery + token + requestTime + key)
```

该项目覆盖的主要端点：

```http
GET /qr_code
GET /qr_code_state/{qr_id}
GET /index_data
GET /search_fund?keyword={keyword}
GET /user_account
GET /account_collect
GET /fund_hold?account_id={account_id}
GET /income_line_data?collect=true&date_type=day
GET /income_data?collect=true
GET /notice
```

验证结论：

1. `/index_data`、`/qr_code`、`/notice` 空 token 可用。
2. `/search_fund?keyword=024418` 空 token 返回 `401 身份信息失效！`，不能用于免登录获取 `code -> fund_id`。
3. 该项目有参考价值：可作为浏览器插件接口签名、二维码登录、账户/持仓接口的样例。
4. 对当前“只取基金关联板块”的目标帮助有限，因为它没有提供免登录板块接口，也不能替代 `/market/v1/fund/batch`。

## 来源记录

- 本地小程序包：`wx8962f01176512bd4`，主包版本观察到 `106`，分包版本观察到 `104`。
- 小程序反编译入口：`pages/index/index`、`pages/options/options`、`pages/search/search`、`pages/fund_page/fund_page`、`packageA/pages/plate_fund/plate_fund`、`packageA/pages/swtich_source/swtich_source`。
- 公开插件资料：[fund-helper API 文档](https://github.com/ChinaCarlos/fund-helper/blob/main/API_README.md)。
- 浏览器插件接口封装：[Ye-Yu-Mo/yjb-api](https://github.com/Ye-Yu-Mo/yjb-api)。
- 公开 `app-api.yangjibao.com` 用例：[skills-api StockIndexCollector](https://github.com/xuya-dev/skills-api/blob/master/src/main/java/ai/skills/api/stockindex/collector/StockIndexCollector.java)。
