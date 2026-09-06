import 'package:flutter/material.dart';
import 'package:moodiary/common/values/webdav.dart';
import 'package:moodiary/presentation/pref.dart';
import 'package:moodiary/presentation/secure_storage.dart';
import 'package:moodiary/services/sync_keeper_service.dart';
import 'package:moodiary/utils/notice_util.dart';
import 'package:moodiary/utils/webdav_util.dart';
import 'package:refreshed/refreshed.dart';

import 'web_dav_state.dart';

class WebDavLogic extends GetxController {
  final WebDavState state = WebDavState();

  WebDavUtil get webDav => WebDavUtil();

  late TextEditingController webDavUrlController = TextEditingController(
      text: state.hasOption.value ? state.currentOptions[0] : null);
  late FocusNode webDavUrlFocusNode = FocusNode();
  late TextEditingController usernameController = TextEditingController(
      text: state.hasOption.value ? state.currentOptions[1] : null);
  late FocusNode usernameFocusNode = FocusNode();
  late TextEditingController passwordController = TextEditingController(
      text: state.hasOption.value ? state.currentOptions[2] : null);
  late FocusNode passwordFocusNode = FocusNode();

  @override
  void onReady() async {
    if (state.hasOption.value) {
      await checkConnectivity();
    }
    await checkHasUserKey();
    super.onReady();
  }

  @override
  void onClose() {
    webDavUrlFocusNode.dispose();
    usernameFocusNode.dispose();
    passwordFocusNode.dispose();
    webDavUrlController.dispose();
    usernameController.dispose();
    passwordController.dispose();
    super.onClose();
  }

  Future<void> checkHasUserKey() async {
    state.hasUserKey.value =
        (await SecureStorageUtil.getValue('userKey')) != null;
  }

  Future<void> checkConnectivity() async {
    state.connectivityStatus.value = WebDavConnectivityStatus.connecting;
    final res = await webDav.checkConnectivity();
    state.connectivityStatus.value = res
        ? WebDavConnectivityStatus.connected
        : WebDavConnectivityStatus.unconnected;
  }

  void unFocus() {
    if (webDavUrlFocusNode.hasFocus) webDavUrlFocusNode.unfocus();
    if (usernameFocusNode.hasFocus) usernameFocusNode.unfocus();
    if (passwordFocusNode.hasFocus) passwordFocusNode.unfocus();
  }

  void submitForm() async {
    if (state.formKey.currentState?.validate() ?? false) {
      unFocus();
      state.formKey.currentState?.save();
      NoticeUtil.showLoading();

      await webDav.updateWebDav(
          baseUrl: webDavUrlController.text,
          username: usernameController.text,
          password: passwordController.text);
      state.hasOption.value = true;
      await checkConnectivity();
      if (state.connectivityStatus.value ==
          WebDavConnectivityStatus.connected) {
        await webDav.initDir();
        // 配置成功即开启自动同步（启动同步 + 改动后同步），并启动跨端轻量
        // 同步守护；用户之后仍可在本页手动关闭。
        if (!(PrefUtil.getValue<bool>('autoSyncSeeded') ?? false)) {
          await PrefUtil.setValue<bool>('autoSync', true);
          await PrefUtil.setValue<bool>('autoSyncAfterChange', true);
          await PrefUtil.setValue<bool>('autoSyncSeeded', true);
        }
        SyncKeeperService().start();
        NoticeUtil.showToast('保存成功');
      } else {
        NoticeUtil.showToast('保存失败，请检查配置');
      }
    }
  }

  DateTime? _firstClickTime; // 用于记录第一次点击时间

  void removeWebDavOption() {
    final currentTime = DateTime.now();

    if (_firstClickTime == null) {
      _firstClickTime = currentTime;
      NoticeUtil.showToast('请再次点击确认删除');
      return;
    }
    if (currentTime.difference(_firstClickTime!).inSeconds <= 2) {
      _firstClickTime = null; // 重置点击时间
      webDavUrlController.text = '';
      usernameController.text = '';
      passwordController.text = '';
      state.hasOption.value = false;
      webDav.removeWebDavOption();
      SyncKeeperService().stop();
      NoticeUtil.showToast('删除成功');
    } else {
      // 超过3秒，重置点击时间并提示
      _firstClickTime = currentTime;
      NoticeUtil.showToast('请再次点击确认删除');
    }
  }

  void setAutoSync(bool value) async {
    await PrefUtil.setValue<bool>('autoSync', value);
    state.autoSync.value = value;
  }

  void setAutoSyncAfterChange(bool value) async {
    await PrefUtil.setValue<bool>('autoSyncAfterChange', value);
    state.autoSyncAfterChange.value = value;
  }

  void setSyncEncryption(bool value) async {
    await PrefUtil.setValue<bool>('syncEncryption', value);
    state.syncEncryption.value = value;
  }
}
