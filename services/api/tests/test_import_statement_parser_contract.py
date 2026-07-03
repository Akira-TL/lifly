from __future__ import annotations

import zipfile
from io import BytesIO

from app.modules.imexport.csv_parser import (
    detect_statement_provider,
    parse_alipay_csv,
    parse_auto_statement,
    parse_wechat_csv,
)


def test_alipay_cashbook_csv_skips_notice_preamble_and_parses_preview_rows() -> None:
    text = "\n".join([
        "特别提示：",
        "1.本记账单内容仅供个人记账使用。",
        "",
        "记录时间,分类,收支类型,金额,备注,账户,来源,标签,",
        "2026-06-30 02:31:43,投资理财,收入,0.11,余额宝-收益发放,余额宝,账单同步,,",
        "2026-06-27 18:33:16,交通,支出,4.00,南京地铁,花呗,账单同步,,",
        "2026-06-20 12:00:00,账户转存,不计收支,100.00,余额转入,余额,手动,,",
    ])
    content = text.encode("gb18030")

    assert detect_statement_provider(content) == "alipay"
    result = parse_auto_statement(content, "local-dev")

    assert result.provider == "alipay"
    assert result.total_rows == 3
    assert result.valid_rows == 2
    assert result.ignored_rows == 1
    assert result.error_rows == 0
    assert result.rows[0].parsed["direction"] == "income"
    assert result.rows[0].parsed["amount"] == 0.11
    assert result.rows[0].parsed["category_hint"] == "投资理财"
    assert result.rows[1].parsed["direction"] == "expense"
    assert result.rows[2].status == "ignored"


def test_wechat_xlsx_detects_header_excel_dates_and_neutral_rows() -> None:
    content = _xlsx_bytes([
        ["微信支付账单明细"],
        ["微信昵称：[Akira]"],
        [""],
        ["----------------------微信支付账单明细列表--------------------"],
        ["交易时间", "交易类型", "交易对方", "商品", "收/支", "金额(元)", "支付方式", "当前状态", "交易单号", "商户单号", "备注"],
        [46201.452835648146, "商户消费", "湖北笑联科技有限公司", "洗衣机", "支出", 3.79, "零钱", "支付成功", "tx_1", "biz_1", "/"],
        [46201.090902777774, "群收款", "李栋", "/", "收入", 66.6, "零钱", "支付成功", "tx_2", "biz_2", "/"],
        [46192.73025462963, "零钱提现", "中国银行", "/", "/", 3928.93, "银行卡", "提现已到账", "tx_3", "/", "服务费¥3.93"],
    ])

    assert detect_statement_provider(content) == "wechat"
    result = parse_wechat_csv(content, "local-dev")

    assert result.provider == "wechat"
    assert result.total_rows == 3
    assert result.valid_rows == 2
    assert result.ignored_rows == 1
    assert result.error_rows == 0
    assert result.rows[0].parsed["direction"] == "expense"
    assert result.rows[0].parsed["amount"] == 3.79
    assert result.rows[0].parsed["merchant"] == "湖北笑联科技有限公司"
    assert result.rows[0].parsed["occurred_at"].startswith("2026-06-28T10:52:05")
    assert result.rows[1].parsed["direction"] == "income"
    assert result.rows[2].status == "ignored"


def test_alipay_parser_handles_official_income_expense_columns() -> None:
    text = "交易时间,交易对方,商品说明,收/支,收入金额,支出金额,交易分类\n" \
        "2026-06-01 08:00:00,便利店,早餐,支出,,12.50,餐饮\n" \
        "2026-06-01 09:00:00,朋友,转账,收入,20.00,,转账\n"
    result = parse_alipay_csv(text.encode("utf-8-sig"), "local-dev")

    assert result.total_rows == 2
    assert result.valid_rows == 2
    assert result.rows[0].parsed["direction"] == "expense"
    assert result.rows[0].parsed["amount"] == 12.5
    assert result.rows[1].parsed["direction"] == "income"
    assert result.rows[1].parsed["amount"] == 20.0


def _xlsx_bytes(rows: list[list[object]]) -> bytes:
    sheet_rows = []
    for row_index, row in enumerate(rows, 1):
        cells = []
        for col_index, value in enumerate(row, 1):
            ref = f"{_col_name(col_index)}{row_index}"
            if isinstance(value, int | float):
                cells.append(f'<c r="{ref}"><v>{value}</v></c>')
            else:
                cells.append(
                    f'<c r="{ref}" t="inlineStr"><is><t>{_xml_escape(str(value))}</t></is></c>'
                )
        sheet_rows.append(f'<row r="{row_index}">{"".join(cells)}</row>')

    sheet_xml = (
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        f'<sheetData>{"".join(sheet_rows)}</sheetData>'
        '</worksheet>'
    )
    output = BytesIO()
    with zipfile.ZipFile(output, "w") as zf:
        zf.writestr("xl/worksheets/sheet1.xml", sheet_xml)
    return output.getvalue()


def _col_name(index: int) -> str:
    value = ""
    while index:
        index, remainder = divmod(index - 1, 26)
        value = chr(ord("A") + remainder) + value
    return value


def _xml_escape(value: str) -> str:
    return (
        value.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace('"', "&quot;")
    )
