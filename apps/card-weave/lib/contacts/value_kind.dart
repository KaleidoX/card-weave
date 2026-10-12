import 'package:flutter/cupertino.dart';

enum ContactValueKind {
  phone('phones', '电话', CupertinoIcons.phone, TextInputType.phone, [
    '手机',
    '住宅',
    '工作',
    '总机',
    '单位传真',
    '住宅传真',
    '寻呼机',
    '其他',
  ]),
  email('emails', '邮箱', CupertinoIcons.mail, TextInputType.emailAddress, [
    '个人',
    '工作',
    '其他',
  ]),
  address(
    'addresses',
    '地址',
    CupertinoIcons.location,
    TextInputType.streetAddress,
    ['住宅', '单位', '其他'],
  ),
  message(
    'instant_messages',
    '即时消息',
    CupertinoIcons.chat_bubble,
    TextInputType.text,
    ['QQ', '微信'],
  ),
  relation('relations', '关联人', CupertinoIcons.person_2, TextInputType.text, [
    '朋友',
    '经理',
    '助理',
    '介绍人',
    '客户',
    '兄弟',
    '姐妹',
    '父亲',
    '母亲',
    '配偶',
    '子女',
  ]);

  const ContactValueKind(
    this.field,
    this.title,
    this.icon,
    this.keyboard,
    this.labels,
  );
  final String field, title;
  final IconData icon;
  final TextInputType keyboard;
  final List<String> labels;
  int get maxBytes => this == address ? 4096 : 1024;
  bool get requiresLabel => this != phone && this != email;
}
