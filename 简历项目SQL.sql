-- 简历数据分析项目
-- 三张表：expense_detail（费用明细）、budget_base（预算基准）、employee_info（人员信息）
-- 数据期间 2026-01~2026-08，金额单位：元

SET NAMES utf8mb4;

-- 建库（可选，改成自己的库名再执行）
-- CREATE DATABASE IF NOT EXISTS expense_db DEFAULT CHARACTER SET utf8mb4;
-- USE expense_db;

-- ============ 一、建表 ============

-- 人员信息表
CREATE TABLE IF NOT EXISTS employee_info (
    姓名     VARCHAR(20) NOT NULL,
    部门     VARCHAR(20) NOT NULL,
    职级     VARCHAR(10) NOT NULL,
    PRIMARY KEY (姓名)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '人员信息表';

-- 预算基准表：每个部门每种费用一个固定月度预算
CREATE TABLE IF NOT EXISTS budget_base (
    部门       VARCHAR(20)    NOT NULL,
    费用类别   VARCHAR(20)    NOT NULL,
    月度预算额 DECIMAL(12, 2) NOT NULL,
    PRIMARY KEY (部门, 费用类别)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '预算基准表';

-- 费用明细表：主键是流水号，外键关联人员和预算
CREATE TABLE IF NOT EXISTS expense_detail (
    流水号     VARCHAR(20)    NOT NULL,
    日期       DATE           NOT NULL,
    部门       VARCHAR(20)    NOT NULL,
    申请人姓名 VARCHAR(20)    NOT NULL,
    费用类别   VARCHAR(20)    NOT NULL,
    金额       DECIMAL(10, 2) NOT NULL,
    审批状态   VARCHAR(10)    NOT NULL,
    PRIMARY KEY (流水号),
    KEY idx_expense_date (日期),
    KEY idx_expense_status (审批状态),
    CONSTRAINT fk_expense_employee FOREIGN KEY (申请人姓名) REFERENCES employee_info (姓名),
    CONSTRAINT fk_expense_budget FOREIGN KEY (部门, 费用类别) REFERENCES budget_base (部门, 费用类别)
) ENGINE = InnoDB DEFAULT CHARSET = utf8mb4 COMMENT = '费用明细表';

-- 如果表已经建好但没有外键，可以单独执行下面两句补上
-- ALTER TABLE expense_detail ADD CONSTRAINT fk_expense_employee FOREIGN KEY (申请人姓名) REFERENCES employee_info (姓名);
-- ALTER TABLE expense_detail ADD CONSTRAINT fk_expense_budget FOREIGN KEY (部门, 费用类别) REFERENCES budget_base (部门, 费用类别);

-- ============ 二、五个查询 ============

-- 查询1：各部门已通过的报销总金额和总笔数
SELECT 部门, SUM(金额) AS 总报销金额, COUNT(*) AS 总报销笔数
FROM expense_detail
WHERE 审批状态 = '已通过'
GROUP BY 部门
ORDER BY 总报销金额 DESC;

-- 查询2：预算达成率预警（达成率 = 实际支出 / 月度预算 x 8个月）
SELECT a.部门, a.费用类别, a.实际支出, b.月度预算额,
       ROUND(a.实际支出 / (b.月度预算额 * 8) * 100, 2) AS `达成率(%)`
FROM (
    SELECT 部门, 费用类别, SUM(金额) AS 实际支出
    FROM expense_detail
    WHERE 审批状态 = '已通过'
    GROUP BY 部门, 费用类别
) a
INNER JOIN budget_base b ON a.部门 = b.部门 AND a.费用类别 = b.费用类别
WHERE ROUND(a.实际支出 / (b.月度预算额 * 8) * 100, 2) > 80
ORDER BY `达成率(%)` DESC;

-- 查询3：每个部门报销金额最高的前3笔（ROW_NUMBER）
SELECT 部门, 申请人姓名, 费用类别, 金额, rn AS 排名
FROM (
    SELECT 部门, 申请人姓名, 费用类别, 金额,
           ROW_NUMBER() OVER (PARTITION BY 部门 ORDER BY 金额 DESC, 日期 ASC, 流水号 ASC) AS rn
    FROM expense_detail
    WHERE 审批状态 = '已通过'
) t
WHERE rn <= 3
ORDER BY 部门, rn;

-- 查询4：全公司每月报销总金额和环比增长率（LAG，1月没有上月数据显示NULL）
SELECT m.月份, m.当月总金额,
       LAG(m.当月总金额) OVER (ORDER BY m.月份) AS 上月总金额,
       ROUND((m.当月总金额 - LAG(m.当月总金额) OVER (ORDER BY m.月份))
             / LAG(m.当月总金额) OVER (ORDER BY m.月份) * 100, 2) AS `环比增长率(%)`
FROM (
    SELECT DATE_FORMAT(日期, '%Y-%m') AS 月份, SUM(金额) AS 当月总金额
    FROM expense_detail
    WHERE 审批状态 = '已通过'
    GROUP BY DATE_FORMAT(日期, '%Y-%m')
) m
ORDER BY m.月份;

-- 查询5：按费用类别对各部门达成率排名（RANK，达成率越高排第1）
SELECT t.费用类别, t.部门,
       ROUND(t.实际支出 / (t.月度预算额 * 8) * 100, 2) AS `达成率(%)`,
       RANK() OVER (PARTITION BY t.费用类别
                    ORDER BY t.实际支出 / (t.月度预算额 * 8) * 100 DESC) AS 排名
FROM (
    SELECT a.部门, a.费用类别, a.实际支出, b.月度预算额
    FROM (
        SELECT 部门, 费用类别, SUM(金额) AS 实际支出
        FROM expense_detail
        WHERE 审批状态 = '已通过'
        GROUP BY 部门, 费用类别
    ) a
    INNER JOIN budget_base b ON a.部门 = b.部门 AND a.费用类别 = b.费用类别
) t
ORDER BY t.费用类别, 排名;

-- ============ 三、视图 ============

-- 视图1：预算达成率预警（同查询2）
CREATE OR REPLACE VIEW v_budget_alert AS
SELECT a.部门, a.费用类别, a.实际支出, b.月度预算额,
       ROUND(a.实际支出 / (b.月度预算额 * 8) * 100, 2) AS `达成率(%)`
FROM (
    SELECT 部门, 费用类别, SUM(金额) AS 实际支出
    FROM expense_detail
    WHERE 审批状态 = '已通过'
    GROUP BY 部门, 费用类别
) a
INNER JOIN budget_base b ON a.部门 = b.部门 AND a.费用类别 = b.费用类别
WHERE ROUND(a.实际支出 / (b.月度预算额 * 8) * 100, 2) > 80
ORDER BY `达成率(%)` DESC;

-- 视图2：月度报销趋势（同查询4）
CREATE OR REPLACE VIEW v_monthly_trend AS
SELECT m.月份, m.当月总金额,
       LAG(m.当月总金额) OVER (ORDER BY m.月份) AS 上月总金额,
       ROUND((m.当月总金额 - LAG(m.当月总金额) OVER (ORDER BY m.月份))
             / LAG(m.当月总金额) OVER (ORDER BY m.月份) * 100, 2) AS `环比增长率(%)`
FROM (
    SELECT DATE_FORMAT(日期, '%Y-%m') AS 月份, SUM(金额) AS 当月总金额
    FROM expense_detail
    WHERE 审批状态 = '已通过'
    GROUP BY DATE_FORMAT(日期, '%Y-%m')
) m
ORDER BY m.月份;

-- 查看视图：SELECT * FROM v_budget_alert;  或者  SELECT * FROM v_monthly_trend;
