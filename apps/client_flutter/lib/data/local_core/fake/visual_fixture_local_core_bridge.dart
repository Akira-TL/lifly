part of '../fake_local_core_bridge.dart';

/// In-memory Local Core dataset for browser/layout review.
///
/// This bridge never opens PowerSync and never writes persistent user data.
/// Recreate it to reset the fixture dataset.
class VisualFixtureLocalCoreBridge extends FakeLocalCoreBridge {
  final DateTime fixtureNow;

  VisualFixtureLocalCoreBridge({DateTime? now})
    : fixtureNow = (now ?? DateTime.now()).toUtc() {
    _seedVisualFixtures();
  }

  @override
  Future<LocalCoreHealth> health() async {
    return LocalCoreHealth(
      status: 'ok',
      mode: 'fake',
      version: 'visual-fixture.v1',
      detail: 'isolated in-memory visual fixture dataset',
      checkedAt: fixtureNow,
    );
  }

  @override
  Future<LocalHomeOverview> getHomeOverview(
    Map<String, Object?> input,
    LocalCoreContext context,
  ) async {
    final summary = await summarizeExpenses(input, context);
    final ledgerOverview = await getLedgerOverview(input, context);
    final categoryBreakdown = await getLedgerCategorySummary({
      ...input,
      'direction': 'expense',
    }, context);
    final financeInsights = await getLedgerInsights(input, context);
    return const LocalHomeOverviewBuilder().build(
      memos: _memos,
      tasks: _tasks,
      transactions: _expenses,
      summary: summary,
      ledgerOverview: ledgerOverview,
      categoryBreakdown: categoryBreakdown,
      financeInsights: financeInsights,
      now: context.effectiveNow,
      sourceMode: input['source_mode'] as String? ?? 'visual_fixture',
    );
  }

  void _seedVisualFixtures() {
    final day = DateTime.utc(
      fixtureNow.year,
      fixtureNow.month,
      fixtureNow.day,
    );

    _memos.addAll([
      _memo(1, 'memo', '本周需要处理的杂事', '快递、眼镜复查、洗衣液、给家里回电话。', ['生活', '本周'], day, 0, 14),
      _memo(2, 'doc', 'Lifly 首页信息密度与跨端布局调整记录', '桌面端提高扫描效率，手机端优先保证触控尺寸；不要通过堆叠卡片制造层级。', ['Lifly', '产品', 'UI'], day, 0, 11),
      _memo(3, 'journal', '周日晚上的一点记录', '把接下来一周真正重要的事情列出来后，焦虑会少很多。', ['日记', '生活'], day, -1, 22),
      _memo(4, 'clip', '文章摘录：设计高信息密度界面的几个原则', '减少重复标签和装饰性边框，让位置、字重、色阶承担层级。', ['设计', '阅读'], day, -1, 18),
      _memo(5, 'memo', '下次去超市', '咖啡豆、鸡蛋、酸奶、纸巾、垃圾袋、洗碗块。', ['购物', '清单', '生活'], day, -2, 20),
      _memo(6, 'doc', '旅行准备清单——证件、交通、住宿与临时变更方案', '护照和证件扫描件离线保存；提前确认机场交通；住宿地址中英文各留一份。', ['旅行', '清单'], day, -3, 16),
      _memo(7, 'memo', '想看的电影', 'Perfect Days、花样年华、海街日记。', ['影音'], day, -4, 23),
      _memo(8, 'journal', '跑步恢复记录', '今天 5km，配速不重要，膝盖没有不适。下次继续控制强度。', ['运动', '健康'], day, -5, 19),
      _memo(9, 'clip', '咖啡冲煮参数', '15g 粉，240g 水，水温 91℃，总时间约 2:30。', ['咖啡', '参数'], day, -6, 8),
      _memo(10, 'memo', '给朋友推荐的几家店', '按安静工作、聚餐、一个人吃三类分别整理。', ['餐厅', '朋友'], day, -7, 21),
      _memo(11, 'doc', '家庭设备保修与序列号备份', '路由器、显示器、键盘、耳机的购买时间和保修截止日期。', ['设备', '归档'], day, -8, 13),
      _memo(12, 'memo', '下个月想做的事情', '整理照片、把书桌灯换掉、找一个周末去徒步。', ['计划'], day, -10, 22),
      _memo(13, 'journal', '最近睡眠状态', '工作日需要把最后一杯咖啡提前到下午两点以前。', ['健康', '睡眠'], day, -12, 9),
      _memo(14, 'clip', '读书摘录：The Design of Everyday Things', '好的设计让正确动作自然发生，而不是依赖用户记住说明。', ['阅读', '设计'], day, -14, 18),
      _memo(15, 'memo', '临时灵感', '把四象限作为属性与色彩，而不是强迫用户进入四块固定区域。', ['Lifly', '灵感', '任务'], day, -16, 15),
      _memo(16, 'doc', '年度订阅整理', '记录续费时间、实际使用频率和是否需要取消。', ['财务', '订阅'], day, -19, 20),
      _memo(17, 'memo', null, '一句没有标题的快速记录，用来检查列表里的无标题状态和长内容截断表现。', ['快速记录'], day, -24, 12),
      _memo(18, 'journal', '月末复盘', '保留真正有用的习惯，删掉只是为了打卡而存在的流程。', ['复盘', '日记'], day, -28, 21),
    ]);

    _tasks.addAll([
      _task(1, '提交本周项目进度总结', '整理完成项、风险和下一阶段计划，发给协作方。', 'urgent', 'todo', day.add(const Duration(hours: 10)), day, 0, 8),
      _task(2, '确认明天上午的体检预约和需要空腹的项目', '检查预约短信、医院位置和交通时间。', 'high', 'todo', day.add(const Duration(hours: 18)), day, 0, 9),
      _task(3, '回复积压的三封重要邮件', null, 'high', 'todo', day.subtract(const Duration(hours: 5)), day, -1, 20),
      _task(4, '完成 Lifly 手机端真实数据布局检查', '重点看长标题、标签、多状态以及底部导航占用。', 'high', 'doing', day.add(const Duration(days: 2, hours: 12)), day, 0, 12),
      _task(5, '缴纳本月宽带费用', null, 'normal', 'todo', day.add(const Duration(days: 2, hours: 11)), day, -1, 10),
      _task(6, '买新的咖啡滤纸', 'V60 02，漂白款。', 'low', 'todo', day.add(const Duration(days: 4, hours: 16)), day, -2, 18),
      _task(7, '整理桌面和抽屉', null, 'low', 'doing', day.add(const Duration(days: 5, hours: 20)), day, -3, 14),
      _task(8, '预约眼镜复查', '最近看远处稍微有点疲劳。', 'normal', 'todo', day.subtract(const Duration(days: 1, hours: 2)), day, -4, 19),
      _task(9, '更新家庭设备保修记录', null, 'normal', 'todo', day.add(const Duration(days: 7, hours: 9)), day, -5, 16),
      _task(10, '周末跑步 8km', '如果膝盖不舒服就改成快走。', 'normal', 'todo', day.add(const Duration(days: 6, hours: 7)), day, -5, 10),
      _task(11, '把旧照片备份到移动硬盘', null, 'low', 'doing', null, day, -8, 21),
      _task(12, '取消不再使用的视频会员自动续费', null, 'normal', 'done', day.subtract(const Duration(days: 2)), day, -6, 11, completedDaysAgo: 2),
      _task(13, '给父母打电话', null, 'normal', 'done', day.subtract(const Duration(days: 3)), day, -7, 20, completedDaysAgo: 3),
      _task(14, '完成上月账单分类', '检查转账不要误算成支出。', 'high', 'done', day.subtract(const Duration(days: 6)), day, -9, 17, completedDaysAgo: 6),
      _task(15, '研究下一次短途旅行目的地', '交通时间控制在三小时左右。', 'low', 'todo', null, day, -11, 13),
    ]);

    _expenses.addAll([
      _tx(1, 'expense', 28.60, '社区咖啡店', '拿铁和可颂', '餐饮', day, 0, 9),
      _tx(2, 'expense', 6.50, '地铁', '通勤', '交通', day, 0, 8),
      _tx(3, 'expense', 136.80, '盒马', '牛奶、鸡蛋、水果和日用品', '购物', day, -1, 20),
      _tx(4, 'expense', 42.00, '面馆', '晚饭', '餐饮', day, -1, 18),
      _tx(5, 'income', 18500.00, '工资', '本月工资到账', '收入', day, -2, 10),
      _tx(6, 'expense', 89.00, '中国移动', '手机套餐', '通讯', day, -2, 9),
      _tx(7, 'expense', 258.00, '京东', '显示器支架', '数码', day, -3, 21),
      _tx(8, 'expense', 18.90, '便利店', '矿泉水和纸巾', '购物', day, -4, 14),
      _tx(9, 'expense', 58.00, '滴滴', '下雨打车回家', '交通', day, -5, 23),
      _tx(10, 'expense', 35.00, '食堂', '午饭', '餐饮', day, -6, 12),
      _tx(11, 'expense', 199.00, '健身房', '月卡续费', '健康', day, -7, 19),
      _tx(12, 'expense', 12.00, '共享单车', '临时骑行', '交通', day, -8, 8),
      _tx(13, 'income', 680.00, '二手平台', '出售闲置键盘', '其他收入', day, -9, 17),
      _tx(14, 'expense', 329.00, '无印良品', '床品和收纳盒', '家居', day, -11, 16),
      _tx(15, 'expense', 4.50, '自动售货机', '苏打水', '餐饮', day, -12, 15),
      _tx(16, 'expense', 76.30, '书店', '两本书', '阅读', day, -14, 20),
      _tx(17, 'expense', 1299.00, '铁路 12306', '往返车票', '旅行', day, -16, 9),
      _tx(18, 'expense', 219.00, '电商平台', '咖啡豆和滤纸', '购物', day, -18, 22),
      _tx(19, 'income', 3500.00, '项目结算', '兼职项目尾款', '其他收入', day, -21, 14),
      _tx(20, 'expense', 1088.00, '房屋服务', '水电燃气与物业合计', '居住', day, -25, 10),
    ]);

    for (var index = 0; index < _visualSessionSeeds.length; index++) {
      final seed = _visualSessionSeeds[index];
      final session = _captureSession(
        index + 1,
        seed.title,
        seed.messages,
        seed.actionTypes,
        committed: seed.committed,
        updatedAt: day.subtract(Duration(hours: index * 5)),
      );
      _captures[session.captureId] = session;
    }
  }

  LocalMemoRecord _memo(
    int index,
    String type,
    String? title,
    String content,
    List<String> tags,
    DateTime day,
    int dayOffset,
    int hour,
  ) {
    final time = day.add(Duration(days: dayOffset, hours: hour));
    return LocalMemoRecord(
      id: 'visual_memo_${index.toString().padLeft(2, '0')}',
      type: type,
      title: title,
      contentMarkdown: content,
      tags: tags,
      status: 'active',
      revision: 1,
      createdAt: time.subtract(const Duration(minutes: 12)),
      updatedAt: time,
    );
  }

  LocalTaskRecord _task(
    int index,
    String title,
    String? description,
    String priority,
    String taskStatus,
    DateTime? dueAt,
    DateTime day,
    int createdDayOffset,
    int createdHour, {
    int? completedDaysAgo,
  }) {
    final createdAt = day.add(
      Duration(days: createdDayOffset, hours: createdHour),
    );
    final completedAt = completedDaysAgo == null
        ? null
        : day.subtract(Duration(days: completedDaysAgo)).add(
            const Duration(hours: 20),
          );
    return LocalTaskRecord(
      id: 'visual_task_${index.toString().padLeft(2, '0')}',
      title: title,
      description: description,
      dueAt: dueAt,
      remindAt: dueAt?.subtract(const Duration(hours: 1)),
      priority: priority,
      taskStatus: taskStatus,
      completedAt: completedAt,
      status: 'active',
      revision: 1,
      createdAt: createdAt,
      updatedAt: completedAt ?? createdAt,
    );
  }

  LocalLedgerTransactionRecord _tx(
    int index,
    String direction,
    double amount,
    String merchant,
    String note,
    String category,
    DateTime day,
    int dayOffset,
    int hour,
  ) {
    final occurredAt = day.add(Duration(days: dayOffset, hours: hour));
    return LocalLedgerTransactionRecord(
      id: 'visual_tx_${index.toString().padLeft(2, '0')}',
      direction: direction,
      amount: amount,
      currency: 'CNY',
      merchant: merchant,
      note: note,
      categoryId: category,
      occurredAt: occurredAt,
      status: 'active',
      revision: 1,
      createdAt: occurredAt,
      updatedAt: occurredAt,
    );
  }

  LocalCaptureSession _captureSession(
    int index,
    String title,
    List<String> messages,
    List<String> actionTypes, {
    required bool committed,
    required DateTime updatedAt,
  }) {
    final captureId = 'visual_capture_${index.toString().padLeft(2, '0')}';
    final turns = <LocalCaptureTurn>[];
    LocalCaptureAction? latestAction;
    for (var messageIndex = 0; messageIndex < messages.length; messageIndex++) {
      final time = updatedAt.subtract(
        Duration(minutes: (messages.length - messageIndex) * 8),
      );
      final actionType = actionTypes[messageIndex % actionTypes.length];
      final action = _visualAction(actionType, messages[messageIndex]);
      latestAction = action;
      final baseIndex = turns.length;
      turns.add(
        LocalCaptureTurn(
          id: '${captureId}_turn_${baseIndex.toString().padLeft(2, '0')}',
          captureId: captureId,
          turnIndex: baseIndex,
          role: 'user',
          text: messages[messageIndex],
          actions: const [],
          selectedActionIndexes: const [],
          resultEntities: const [],
          turnStatus: 'accepted',
          createdAt: time,
          updatedAt: time,
        ),
      );
      final actionTurnCommitted = committed && messageIndex == messages.length - 1;
      turns.add(
        LocalCaptureTurn(
          id: '${captureId}_turn_${(baseIndex + 1).toString().padLeft(2, '0')}',
          captureId: captureId,
          turnIndex: baseIndex + 1,
          role: 'assistant',
          text: null,
          actions: [action],
          selectedActionIndexes: actionTurnCommitted ? const [0] : const [],
          resultEntities: actionTurnCommitted
              ? [
                  LocalCoreEntityRef(
                    type: _entityTypeForAction(actionType),
                    id: 'visual_result_${index.toString().padLeft(2, '0')}',
                  ),
                ]
              : const [],
          undoToken: actionTurnCommitted ? 'visual_undo_$index' : null,
          turnStatus: actionTurnCommitted ? 'committed' : 'parsed',
          createdAt: time.add(const Duration(seconds: 1)),
          updatedAt: time.add(const Duration(seconds: 1)),
        ),
      );
    }

    return LocalCaptureSession(
      captureId: captureId,
      originalText: title,
      actions: latestAction == null ? const [] : [latestAction],
      requiresConfirmation: !committed,
      committed: committed,
      sessionStatus: 'active',
      sourceChannel: 'flutter',
      createdAt: updatedAt.subtract(const Duration(hours: 1)),
      updatedAt: updatedAt,
      expiresAt: updatedAt.add(const Duration(days: 30)),
      committedAt: committed ? updatedAt : null,
      turns: turns,
    );
  }

  LocalCaptureAction _visualAction(String type, String text) {
    final payload = switch (type) {
      'task_create' => <String, Object?>{
        'title': text,
        'priority': 'normal',
      },
      'expense_create' => <String, Object?>{
        'direction': 'expense',
        'amount': 42.8,
        'currency': 'CNY',
        'merchant': '视觉测试商户',
        'note': text,
      },
      _ => <String, Object?>{
        'type': 'memo',
        'title': null,
        'content_markdown': text,
        'tags': ['AI'],
      },
    };
    return LocalCaptureAction(
      type: type,
      payload: payload,
      confidence: 0.86,
      rawText: text,
    );
  }

  String _entityTypeForAction(String actionType) {
    return switch (actionType) {
      'task_create' => 'task',
      'expense_create' => 'ledger_transaction',
      _ => 'memo',
    };
  }
}

class _VisualSessionSeed {
  final String title;
  final List<String> messages;
  final List<String> actionTypes;
  final bool committed;

  const _VisualSessionSeed({
    required this.title,
    required this.messages,
    required this.actionTypes,
    required this.committed,
  });
}

const _visualSessionSeeds = <_VisualSessionSeed>[
  _VisualSessionSeed(
    title: '整理今天的任务和晚上的安排',
    messages: ['提醒我下午把周报发出去', '晚上七点去跑步，结束后买牛奶'],
    actionTypes: ['task_create', 'task_create'],
    committed: true,
  ),
  _VisualSessionSeed(
    title: '记录午饭和咖啡',
    messages: ['午饭 35 元', '下午咖啡 28.6 元'],
    actionTypes: ['expense_create'],
    committed: true,
  ),
  _VisualSessionSeed(
    title: '旅行准备清单',
    messages: ['记一下出发前确认证件和充电器', '再加一条：提前一天在线值机'],
    actionTypes: ['memo_create'],
    committed: false,
  ),
  _VisualSessionSeed(
    title: '周末安排',
    messages: ['提醒我周六上午整理房间', '下午去书店看看设计类的新书'],
    actionTypes: ['task_create', 'memo_create'],
    committed: false,
  ),
  _VisualSessionSeed(
    title: '快速记账',
    messages: ['打车 58 元回家'],
    actionTypes: ['expense_create'],
    committed: true,
  ),
  _VisualSessionSeed(
    title: '产品设计灵感',
    messages: ['备忘：高信息密度不等于把所有字体都缩小'],
    actionTypes: ['memo_create'],
    committed: false,
  ),
  _VisualSessionSeed(
    title: '下周要处理的事情',
    messages: ['提醒我预约眼镜复查', '记得取消不用的视频会员'],
    actionTypes: ['task_create'],
    committed: true,
  ),
  _VisualSessionSeed(
    title: '生活记录',
    messages: ['记一下今天跑了 5km，膝盖状态正常'],
    actionTypes: ['memo_create'],
    committed: false,
  ),
];
