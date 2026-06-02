# apizero
申请地址：[https://apizero.cn/marketplace/barcode-lookup](https://apizero.cn/marketplace/barcode-lookup)

## 免费额度
无 Key 调用（按 IP 限制）：每日 20 次 · QPS 1

携带 Key 调用（注册即可获取）：每日 200 次 · QPS 2

## 接入文档
https://apizero.cn/aidocs/barcode-lookup/raw.md

## 接口地址
https://v1.apizero.cn/api/barcode-lookup

## 请求参数
| 参数名	| 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| barcode	| string	| 必填	 | 8~13 位纯数字条形码。支持 EAN-13、UPC-A、EAN-8、UPC-E 等主流标准。示例：6921168509256 |
| mode	| string	| 可选	 | 保留参数：mode=image 时返回该商品的图片二进制（不计费、公开访问，主要由响应中的 image 字段链接自动调用）。示例：image |

## 请求头
| 参数名	| 必填	| 说明 |
| --- | --- | --- |
| Authorization	| 可选	 | 可选 API Key 鉴权。未登录每天有 20 次免费体验额度；登录用户每天 200 次免费 |

## 返回参数（响应字段）
| 字段名	| 类型	| 说明 |
| --- | --- | --- |
| code	| `integer`	| 业务状态码，0 表示成功。示例：0 |
| msg	| `string`	| 人类可读的状态消息。示例：成功 |
| data.barcode	| `string`	| 回显的输入条形码。示例：6921168509256 |
| data.found	| `boolean`	| 是否查到该商品；false 时其余字段均为 null。示例：true |
| data.name	| `string/null`	| 商品名称。示例：农夫山泉 饮用天然水550ml |
| data.brand	| `string/null`	| 品牌。示例：农夫山泉 |
| data.manufacturer	| `string/null`	| 生产厂商 / 经销商。示例：农夫山泉股份有限公司 |
| data.spec	| `string/null`	| 规格（容量 / 重量 / 包装等）。示例：550ml |
| data.price	| `number/null`	| 参考价（人民币元，浮点；仅作参考，非实时市场价）。示例：1.5 |
| data.category	| `string/null`	| 商品分类（部分商品可能为 null）。示例：null |
| data.description	| `string/null`	| 附加描述（部分商品可能为 null）。示例：null |
| data.image	| `string/null`	| 商品图片 URL（自有 CDN 代理）；found=false 时为 null。示例：https://v1.apizero.cn/api/barcode-lookup?mode=image&barcode=6921168509256 |
| request_id	| `string`	| 本次请求 ID（出问题时反馈给客服可快速定位）。示例：mqx8x12345abc |

## 返回示例
```json
{
    "code": 0,
    "msg": "成功",
    "data": {
        "barcode": "6921168509256",
        "found": true,
        "name": "农夫山泉 饮用天然水550ml",
        "brand": "农夫山泉",
        "manufacturer": "农夫山泉股份有限公司",
        "spec": "550ml",
        "price": 1.5,
        "category": null,
        "description": null,
        "image": "https://v1.apizero.cn/api/barcode-lookup?mode=image&barcode=6921168509256"
    },
    "request_id": "mqx8x12345abc"
}
```

# apizero-pro
申请地址：[https://apizero.cn/marketplace/barcode-gs1](https://apizero.cn/marketplace/barcode-gs1)

## 免费额度
无 Key 调用（按 IP 限制）：每日 20 次 · QPS 1

携带 Key 调用（注册即可获取）：每日 20 次 · QPS 2

## 接入文档
https://apizero.cn/aidocs/barcode-gs1/raw.md

## 接口地址
https://v1.apizero.cn/api/barcode-gs1

## 请求参数
| 参数名	| 类型 | 必填	| 说明 |
| --- | --- | --- | --- |
| code	| string	| 必填	| 商品条形码(8/12/13/14 位纯数字，或 16 位 AI(01) 前缀 + GTIN-14)。示例：6921168509256 |

## 请求头
| 参数名	| 必填	| 说明 |
| --- | --- | --- |
| Authorization	| 可选	 | 登录用户传 API Key 享用更高额度；匿名调用每天 20 次免费 |

## 返回参数（响应字段）
| 字段名	| 类型	| 说明 |
| --- | --- | --- |
| barcode	| string	| 13 位标准 EAN-13 条码 |
| gtin14	| string	| 14 位 GTIN（左侧补 0 标准化） |
| found	| boolean	| 是否在 GS1 中国数据库找到；false 时其余业务字段为 null |
| registered	| boolean	| 条码是否已在中国物品编码中心正式注册 |
| registration_message	| string	| 注册状态说明文本 |
| name	| string	| 完整产品名（含品牌+规格） |
| brand	| string	| 品牌名称 |
| general_name	| string	| 产品通用名（如"奶酪（易腐坏）"） |
| feature	| string	| 产品特征描述 |
| category	| string	| 产品分类（含 GPC 分类编号，如"奶酪（易腐坏）(10000028)"） |
| specification	| string	| 规格（如 90克 / 550ml） | 
| net_content	| string	| 净含量 |
| sale_date	| string	| 上市日期（YYYY-MM-DD） |
| manufacturer	| string	| 发布企业名称（官方注册主体） |
| images	| string[]	| 官方商品图 URL 数组（gds.org.cn 域名） |
| qr_active_date	| string	| 二维码激活日期（YYYY年MM月DD日） |
| product_create_date	| string	| 产品信息创建日期（YYYY年MM月DD日） |
| company_register_date	| string	| 企业在编码中心的注册日期（YYYY年MM月DD日） |
| use_days	| integer	| 条码从登记到现在已用天数 |
| country	| string	| 生产国 / 产地（部分备源提供，主源可能为 null） |
| address	| string	| 企业地址（部分备源提供，主源可能为 null） |
| price	| string	| 参考售价（部分备源提供，主源可能为 null） |
| category_code	| string	| GPC 全球品类编码 / 厂商识别代码（部分源提供） |

## 返回示例
```json
{
    "code": 0,
    "msg": "成功",
    "data": {
        "barcode": "6907992700199",
        "gtin14": "06907992700199",
        "found": true,
        "registered": true,
        "registration_message": "该商品条码已经在中国物品编码中心注册，编码信息已按规定通报。",
        "name": "伊利儿童奶酪棒香草冰淇淋味再制干酪",
        "brand": "伊利",
        "general_name": "奶酪（易腐坏）",
        "feature": "伊利儿童奶酪棒香草冰淇淋味再制干酪",
        "category": "奶酪（易腐坏）(10000028)",
        "specification": "90克",
        "net_content": "90克",
        "sale_date": null,
        "manufacturer": "内蒙古伊利实业集团股份有限公司",
        "images": [
            "https:\/\/www.gds.org.cn\/userfile\/uploada\/gra\/sj201210093039959369\/06907992700199\/06907992700199.1.jpg"
        ],
        "qr_active_date": null,
        "product_create_date": "2019年11月18日",
        "company_register_date": null,
        "use_days": 2366,
        "country": null,
        "address": null,
        "price": null,
        "category_code": null
    },
    "request_id": "mp0vcq0fab827132"
}
```

# apibyte
申请地址：[https://apibyte.cn/marketplace/barcode](https://apibyte.cn/marketplace/barcode)

## 免费额度
无 Key 调用（按 IP 限制）：每日 0 次 · QPS 0

携带 Key 调用（注册即可获取）：每日 100 次 · QPS 5

## 接口地址
https://apione.apibyte.cn/api/barcode

## 请求参数
| 参数名	| 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| key	| string	| 必填	 | API Key，也可通过 Header Authorization: Bearer {key} 传入 |
| barcode	| string	| 必填	 | 商品条形码，8~13位数字 |

## 响应参数
| 参数名	| 类型 | 说明
| --- | --- | --- |
| barcode	| string	| 查询的条形码 |
| found	| boolean	| 是否查询到商品 |
| goods_name	| string	| 商品名称 |
| brand	| string	| 品牌/商标 |
| company	| string	| 生产厂商 |
| specification	| string	| 规格 |
| category	| string	| 商品分类 |
| description	| string	| 商品描述 |
| image	| string	| 商品图片URL |
| price	| string	| 参考价格 |

## 响应示例
```json
{
  "msg": "success",
  "code": 200,
  "data": {
    "brand": "可口可乐",
    "found": true,
    "image": "https://example.com/product.jpg",
    "price": "12.90",
    "barcode": "6920354825124",
    "company": "中粮可口可乐饮料有限公司",
    "category": "饮料",
    "goods_name": "可口可乐 碳酸饮料 330ml*6",
    "description": "",
    "specification": "330ml*6"
  },
  "time": 1770590000
}
```

# rollapi
申请地址：[https://www.mxnzp.com?ic=WTBYLO](https://www.mxnzp.com?ic=WTBYLO)

## 免费额度
无 Key 调用（按 IP 限制）：每日 0 次 · QPS 0

携带 Key 调用（注册即可获取）：每日 1000 次 · QPS 1

## 接口地址
https://www.mxnzp.com/api/barcode/goods/details

接口请求示例： https://www.mxnzp.com/api/barcode/goods/details?barcode=6902538005141&app_id=不再提供请自主申请&app_secret=不再提供请自主申请

## 请求参数
| 参数名	| 类型 | 必填 | 说明 |
| --- | --- | --- | --- |
| barcode	| string	| 必填	 | 商品条形码，8~13位数字 |
| app_id	| string	| 必填	 | 应用 ID，用于验证请求来源 |
| app_secret	| string	| 必填	 | 应用密钥，用于验证请求来源 |

## 响应参数
| 参数名	| 类型 | 说明
| --- | --- | --- |
| goodsName	| string	| 商品名称 |
| barcode	| string	| 查询的条形码 |
| price	| string	| 参考价格 |
| brand	| string	| 品牌 |
| supplier	| string	| 厂商 |
| standard	| string	| 规格 |


## 响应示例
```json
{
    "code": 1,
    "msg": "数据返回成功",
    "data": {
        "goodsName": "脉动维生素饮料（水蜜桃口味）600ml",
        "barcode": "6902538005141",
        "price": "3.80",
        "brand": "达能",
        "supplier": "达能(中国)食品饮料有限公司",
        "standard": "600ml"
    }
}
```