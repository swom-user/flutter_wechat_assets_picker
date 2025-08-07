// Copyright 2019 The FlutterCandies author. All rights reserved.
// Use of this source code is governed by an Apache license that can be found
// in the LICENSE file.

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';
import 'package:provider/provider.dart';
import 'package:wechat_assets_picker/src/widget/toast/asset_toast.dart';
import 'package:wechat_picker_library/wechat_picker_library.dart';

import '../constants/constants.dart';
import '../constants/enums.dart';
import '../constants/typedefs.dart';
import '../delegates/asset_picker_text_delegate.dart';
import '../internals/singleton.dart';
import '../models/path_wrapper.dart';
import '../provider/asset_picker_provider.dart';
import '../widget/asset_picker.dart';
import '../widget/asset_picker_app_bar.dart';
import '../widget/asset_picker_viewer.dart';
import '../widget/builder/asset_entity_grid_item_builder.dart';

/// The delegate to build the whole picker's components.
///
/// By extending the delegate, you can customize every components on you own.
/// Delegate requires two generic types:
///  * [Asset] The type of your assets. Defaults to [AssetEntity].
///  * [Path] The type of your paths. Defaults to [AssetPathEntity].
abstract class AssetPickerBuilderDelegate<Asset, Path> {
  AssetPickerBuilderDelegate({
    required this.initialPermission,
    this.gridCount = 4,
    this.pickerTheme,
    this.specialItemPosition = SpecialItemPosition.none,
    this.specialItemBuilder,
    this.loadingIndicatorBuilder,
    this.selectPredicate,
    this.shouldRevertGrid,
    this.limitedPermissionOverlayPredicate,
    this.pathNameBuilder,
    this.assetsChangeCallback,
    this.assetsChangeRefreshPredicate,
    this.isPrivateMode = false,
    Color? themeColor,
    AssetPickerTextDelegate? textDelegate,
    Locale? locale,
  })  : assert(gridCount > 0, 'gridCount must be greater than 0.'),
        assert(
          pickerTheme == null || themeColor == null,
          'Theme and theme color cannot be set at the same time.',
        ),
        themeColor = pickerTheme?.colorScheme.secondary ??
            themeColor ??
            defaultThemeColorWeChat {
    Singleton.textDelegate =
        textDelegate ?? assetPickerTextDelegateFromLocale(locale);
  }

  /// The [PermissionState] when the picker is called.
  /// 当选择器被拉起时的权限状态
  final PermissionState initialPermission;

  /// Assets count for the picker.
  /// 资源网格数
  final int gridCount;

  /// Main color for the picker.
  /// 选择器的主题色
  final Color? themeColor;

  final bool isPrivateMode;

  /// Theme for the picker.
  /// 选择器的主题
  ///
  /// Usually the WeChat uses the dark version (dark background color)
  /// for the picker. However, some others want a light or a custom version.
  ///
  /// 通常情况下微信选择器使用的是暗色（暗色背景）的主题，
  /// 但某些情况下开发者需要亮色或自定义主题。
  final ThemeData? pickerTheme;

  /// Allow users set a special item in the picker with several positions.
  /// 允许用户在选择器中添加一个自定义 item，并指定位置
  final SpecialItemPosition specialItemPosition;

  /// The widget builder for the the special item.
  /// 自定义 item 的构造方法
  final SpecialItemBuilder<Path>? specialItemBuilder;

  /// Indicates the loading status for the builder.
  /// 指示目前加载的状态
  final LoadingIndicatorBuilder? loadingIndicatorBuilder;

  /// {@macro wechat_assets_picker.AssetSelectPredicate}
  final AssetSelectPredicate<Asset>? selectPredicate;

  /// The [ScrollController] for the preview grid.
  final ScrollController gridScrollController = ScrollController();

  /// If path switcher opened.
  /// 是否正在进行路径选择
  final ValueNotifier<bool> isSwitchingPath = ValueNotifier<bool>(false);

  /// The [GlobalKey] for [assetsGridBuilder] to locate the [ScrollView.center].
  /// [assetsGridBuilder] 用于定位 [ScrollView.center] 的 [GlobalKey]
  final GlobalKey gridRevertKey = GlobalKey();

  /// Whether the assets grid should revert.
  /// 判断资源网格是否需要倒序排列
  ///
  /// [Null] means judging by [isAppleOS].
  /// 使用 [Null] 即使用 [isAppleOS] 进行判断。
  final bool? shouldRevertGrid;

  /// {@macro wechat_assets_picker.LimitedPermissionOverlayPredicate}
  final LimitedPermissionOverlayPredicate? limitedPermissionOverlayPredicate;

  /// {@macro wechat_assets_picker.PathNameBuilder}
  final PathNameBuilder<AssetPathEntity>? pathNameBuilder;

  /// {@macro wechat_assets_picker.AssetsChangeCallback}
  final AssetsChangeCallback<AssetPathEntity>? assetsChangeCallback;

  /// {@macro wechat_assets_picker.AssetsChangeRefreshPredicate}
  final AssetsChangeRefreshPredicate<AssetPathEntity>?
      assetsChangeRefreshPredicate;

  /// [ThemeData] for the picker.
  /// 选择器使用的主题
  ThemeData get theme => pickerTheme ?? AssetPicker.themeData(themeColor);

  /// Return a system ui overlay style according to
  /// the brightness of the theme data.
  /// 根据主题返回状态栏的明暗样式
  SystemUiOverlayStyle get overlayStyle {
    if (theme.appBarTheme.systemOverlayStyle != null) {
      return theme.appBarTheme.systemOverlayStyle!;
    }
    return SystemUiOverlayStyle(
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
      statusBarIconBrightness: theme.effectiveBrightness,
      statusBarBrightness: theme.effectiveBrightness.reverse,
    );
  }

  /// The color for interactive texts.
  /// 可交互的文字的颜色
  Color interactiveTextColor(BuildContext context) => Color.lerp(
        context.iconTheme.color?.withOpacity(.7) ?? Colors.white,
        Colors.blueAccent,
        0.4,
      )!;

  /// Whether the current platform is Apple OS.
  /// 当前平台是否苹果系列系统 (iOS & MacOS)
  bool isAppleOS(BuildContext context) => switch (context.theme.platform) {
        TargetPlatform.iOS || TargetPlatform.macOS => true,
        _ => false,
      };

  /// Whether the picker is under the single asset mode.
  /// 选择器是否为单选模式
  bool get isSingleAssetMode;

  /// Whether the delegate should build the special item.
  /// 是否需要构建自定义 item
  bool get shouldBuildSpecialItem =>
      specialItemPosition != SpecialItemPosition.none &&
      specialItemBuilder != null;

  /// Space between assets item widget.
  /// 资源部件之间的间隔
  double get itemSpacing => 2;

  /// Item's height in app bar.
  /// 顶栏内各个组件的统一高度
  double get appBarItemHeight => 32;

  /// Blur radius in Apple OS layout mode.
  /// 苹果系列系统布局方式下的模糊度
  double get appleOSBlurRadius => 10;

  /// Height for the bottom occupied section.
  /// 底部区域占用的高度
  double get bottomSectionHeight =>
      bottomActionBarHeight + permissionLimitedBarHeight;

  /// Height for bottom action bar.
  /// 底部操作栏的高度
  double get bottomActionBarHeight => kToolbarHeight / 1.1;

  /// Height for the permission limited bar.
  /// 权限受限栏的高度
  double get permissionLimitedBarHeight => isPermissionLimited ? 75 : 0;

  @Deprecated('Use permissionNotifier instead. This will be removed in 10.0.0')
  ValueNotifier<PermissionState> get permission => permissionNotifier;

  /// Notifier for the current [PermissionState].
  /// 当前 [PermissionState] 的监听
  late final permissionNotifier = ValueNotifier<PermissionState>(
    initialPermission,
  );

  late final permissionOverlayDisplay = ValueNotifier<bool>(
    limitedPermissionOverlayPredicate?.call(permissionNotifier.value) ??
        (permissionNotifier.value == PermissionState.limited),
  );

  /// Whether the permission is limited currently.
  /// 当前的权限是否为受限
  bool get isPermissionLimited =>
      permissionNotifier.value == PermissionState.limited;

  bool effectiveShouldRevertGrid(BuildContext context) =>
      shouldRevertGrid ?? isAppleOS(context);

  AssetPickerTextDelegate get textDelegate => Singleton.textDelegate;

  AssetPickerTextDelegate get semanticsTextDelegate =>
      Singleton.textDelegate.semanticsTextDelegate;

  /// Keep a `initState` method to sync with [State].
  /// 保留一个 `initState` 方法与 [State] 同步。
  @mustCallSuper
  Future<void> initState(AssetPickerState<Asset, Path> state) async {
    await PhotoManager.clearFileCache();
  }

  /// Keep a `dispose` method to sync with [State].
  /// 保留一个 `dispose` 方法与 [State] 同步。
  @mustCallSuper
  void dispose() {
    Singleton.scrollPosition = null;
    gridScrollController.dispose();
    isSwitchingPath.dispose();
    permissionNotifier.dispose();
    permissionOverlayDisplay.dispose();
  }

  /// The method to select assets. Delegates can implement this method
  /// to involve with predications, callbacks, etc.
  /// 选择资源的方法。自定义的 delegate 可以通过实现该方法，整合判断、回调等操作。
  @protected
  void selectAsset(
    BuildContext context,
    Asset asset,
    int index,
    bool selected,
    bool isMultipleSelection,
  );

  /// Throttle the assets changing calls.
  Completer<void>? onAssetsChangedLock;

  /// Called when assets changed and obtained notifications from the OS.
  /// 系统发出资源变更的通知时调用的方法
  Future<void> onAssetsChanged(MethodCall call, StateSetter setState) async {}

  /// Determine how to browse assets in the viewer.
  /// 定义如何在查看器中浏览资源
  Future<void> viewAsset(
    BuildContext context,
    int? index,
    List<AssetEntity>? currentAssets,
    Asset currentAsset,
  );

  /// Yes, the build method.
  /// 没错，是它是它就是它，我们亲爱的 build 方法~
  Widget build(BuildContext context);

  /// Path entity select widget builder.
  /// 路径选择部件构建
  Widget pathEntitySelector(BuildContext context);

  /// Item widgets for path entity selector.
  /// 路径单独条目选择组件
  Widget pathEntityWidget({
    required BuildContext context,
    required PathWrapper<Path> item,
  });

  /// A backdrop widget behind the [pathEntityListWidget].
  /// 在 [pathEntityListWidget] 后面的遮罩层
  ///
  /// While the picker is switching path, this will displayed.
  /// If the user tapped on it, it'll collapse the list widget.
  ///
  /// 当选择器正在选择路径时，它会出现。用户点击它时，列表会折叠收起。
  Widget pathEntityListBackdrop(BuildContext context);

  /// List widget for path entities.
  /// 路径选择列表组件
  Widget pathEntityListWidget(BuildContext context);

  /// Confirm button.
  /// 确认按钮
  Widget confirmButton(BuildContext context);

  /// Audio asset type indicator.
  /// 音频类型资源指示
  Widget audioIndicator(BuildContext context, Asset asset);

  /// Video asset type indicator.
  /// 视频类型资源指示
  Widget videoIndicator(BuildContext context, Asset asset);

  /// Animated backdrop widget for items.
  /// 部件选中时的动画遮罩部件
  Widget selectedBackdrop(
    BuildContext context,
    List<AssetEntity>? currentAssets,
    int index,
    Asset asset,
    bool isMultipleSelection,
  );

  /// Indicator for assets selected status.
  /// 资源是否已选的指示器
  Widget selectIndicator(
    BuildContext context,
    int index,
    Asset asset,
    bool isMultipleSelection,
  );

  /// The main grid view builder for assets.
  /// 主要的资源查看网格部件
  Widget assetsGridBuilder(
    BuildContext context,
    bool isMultipleSelection,
    String requestType,
  );

  /// Indicates how would the grid found a reusable [RenderObject] through [id].
  /// 为 Grid 布局指示如何找到可复用的 [RenderObject]。
  ///
  /// See also:
  ///  * [SliverChildBuilderDelegate.findChildIndexCallback].
  int? findChildIndexBuilder({
    required String id,
    required List<Asset> assets,
    int placeholderCount = 0,
  }) =>
      null;

  /// The function which return items count for the assets' grid.
  /// 为资源列表提供内容数量计算的方法
  int assetsGridItemCount({
    required BuildContext context,
    required List<Asset> assets,
    int placeholderCount = 0,
  });

  /// The item builder for the assets' grid.
  /// 资源列表项的构建
  Widget assetGridItemBuilder(
    BuildContext context,
    int index,
    List<Asset> currentAssets,
    bool isMultipleSelection,
  );

  /// The [Semantics] builder for the assets' grid.
  /// 资源列表项的语义构建
  Widget assetGridItemSemanticsBuilder(
    BuildContext context,
    int index,
    Asset asset,
    bool isMultipleSelection,
    Widget child,
  );

  /// The item builder for audio type of asset.
  /// 音频资源的部件构建
  Widget audioItemBuilder(
    BuildContext context,
    int index,
    Asset asset,
  );

  /// The item builder for images and video type of asset.
  /// 图片和视频资源的部件构建
  Widget imageAndVideoItemBuilder(
    BuildContext context,
    int index,
    Asset asset,
  );

  /// Preview button to preview selected assets.
  /// 预览已选资源的按钮
  Widget previewButton(BuildContext context);

  /// Custom app bar for the picker.
  /// 选择器自定义的顶栏
  PreferredSizeWidget appBar(BuildContext context);

  /// The preferred size of [appBar].
  /// [appBar] 的首选大小。
  ///
  /// If it's null, typically means the widget hasn't been built yet.
  /// 为空则意味着 widget 未 build。
  Size? appBarPreferredSize;

  /// Layout for Apple OS devices.
  /// 苹果系列设备的选择器布局
  Widget appleOSLayout(BuildContext context, bool isMultipleSelection);

  /// Layout for Android devices.
  /// Android设备的选择器布局
  Widget androidLayout(BuildContext context, bool isMultipleSelection);

  /// Loading indicator.
  /// 加载指示器
  ///
  /// Subclasses need to implement this due to the generic type limitation, and
  /// not all delegates use [AssetPickerProvider].
  ///
  /// See also:
  /// - [DefaultAssetPickerBuilderDelegate.loadingIndicator] as an example.
  Widget loadingIndicator(BuildContext context);

  /// GIF image type indicator.
  /// GIF 类型图片指示
  Widget gifIndicator(BuildContext context, Asset asset) {
    return Positioned.fill(
      top: null,
      child: Container(
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: AlignmentDirectional.bottomCenter,
            end: AlignmentDirectional.topCenter,
            colors: <Color>[theme.dividerColor, Colors.transparent],
          ),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
          decoration: !isAppleOS(context)
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: theme.iconTheme.color!.withOpacity(0.75),
                )
              : null,
          child: ScaleText(
            textDelegate.gifIndicator,
            style: TextStyle(
              color: isAppleOS(context)
                  ? theme.textTheme.bodyMedium?.color
                  : theme.primaryColor,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
            semanticsLabel: semanticsTextDelegate.gifIndicator,
            strutStyle: const StrutStyle(forceStrutHeight: true, height: 1),
          ),
        ),
      ),
    );
  }

  /// Indicator when the asset cannot be selected.
  /// 当资源无法被选中时的遮罩
  Widget itemBannedIndicator(BuildContext context, Asset asset) {
    return Consumer<AssetPickerProvider<Asset, Path>>(
      builder: (_, AssetPickerProvider<Asset, Path> p, __) {
        if (!p.selectedAssets.contains(asset) && p.selectedMaximumAssets) {
          return Container(
            color: theme.colorScheme.background.withOpacity(.85),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  /// Indicator when no assets were found from the current path.
  /// 当前目录下无资源的显示
  Widget emptyIndicator(BuildContext context) {
    return ScaleText(
      textDelegate.emptyList,
      maxScaleFactor: 1.5,
      semanticsLabel: semanticsTextDelegate.emptyList,
    );
  }

  /// Item widgets when the thumb data load failed.
  /// 资源缩略数据加载失败时使用的部件
  Widget failedItemBuilder(BuildContext context) {
    return Center(
      child: ScaleText(
        textDelegate.loadFailed,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 18),
        semanticsLabel: semanticsTextDelegate.loadFailed,
      ),
    );
  }

  /// The effective direction for the assets grid.
  /// 网格实际的方向
  ///
  /// By default, the direction will be reversed if it's iOS/macOS.
  /// 默认情况下，在 iOS/macOS 上方向会反向。
  TextDirection effectiveGridDirection(BuildContext context) {
    final TextDirection od = Directionality.of(context);
    if (effectiveShouldRevertGrid(context)) {
      if (od == TextDirection.ltr) {
        return TextDirection.rtl;
      }
      return TextDirection.ltr;
    }
    return od;
  }

  /// The tip widget displays when the access is limited.
  /// 当访问受限时在底部展示的提示
  Widget accessLimitedBottomTip(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Feedback.forTap(context);
        PhotoManager.openSetting();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        height: permissionLimitedBarHeight,
        color: theme.primaryColor.withOpacity(isAppleOS(context) ? 0.90 : 1),
        child: Row(
          children: <Widget>[
            const SizedBox(width: 5),
            Icon(
              Icons.warning,
              color: Colors.orange[400]!.withOpacity(.8),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: ScaleText(
                textDelegate.accessAllTip,
                style: context.textTheme.bodySmall?.copyWith(
                  fontSize: 14,
                ),
                semanticsLabel: semanticsTextDelegate.accessAllTip,
              ),
            ),
            Icon(
              Icons.keyboard_arrow_right,
              color: context.iconTheme.color?.withOpacity(.5),
            ),
          ],
        ),
      ),
    );
  }

  /// Action bar widget aligned to bottom.
  /// 底部操作栏部件
  Widget bottomActionBar(BuildContext context) {
    Widget child = Container(
      height: bottomActionBarHeight + context.bottomPadding,
      padding: const EdgeInsets.symmetric(horizontal: 20).copyWith(
        bottom: context.bottomPadding,
      ),
      color: theme.primaryColor.withOpacity(isAppleOS(context) ? 0.90 : 1),
      child: Row(
        children: <Widget>[
          previewButton(context),
          const Spacer(),
          confirmButton(context),
        ],
      ),
    );
    if (isPermissionLimited) {
      child = Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[accessLimitedBottomTip(context), child],
      );
    }
    child = ClipRect(
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(
          sigmaX: appleOSBlurRadius,
          sigmaY: appleOSBlurRadius,
        ),
        child: child,
      ),
    );
    return child;
  }

  /// Back button.
  /// 返回按钮
  Widget backButton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: IconButton(
        onPressed: () {
          Navigator.maybeOf(context)?.maybePop();
        },
        tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
        icon: Icon(
          Icons.close,
          semanticLabel: MaterialLocalizations.of(context).closeButtonTooltip,
        ),
      ),
    );
  }

  /// The overlay when the permission is limited on iOS.
  @Deprecated('Use permissionOverlay instead. This will be removed in 10.0.0')
  Widget iOSPermissionOverlay(BuildContext context) {
    return permissionOverlay(context);
  }

  /// The overlay when the permission is limited.
  Widget permissionOverlay(BuildContext context) {
    final Size size = MediaQuery.sizeOf(context);
    final Widget closeButton = Container(
      margin: const EdgeInsetsDirectional.only(start: 16, top: 4),
      alignment: AlignmentDirectional.centerStart,
      child: IconButton(
        onPressed: () {
          Navigator.maybeOf(context)?.maybePop();
        },
        icon: const Icon(Icons.close),
        padding: EdgeInsets.zero,
        constraints: BoxConstraints.tight(const Size.square(32)),
        tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
      ),
    );

    final Widget limitedTips = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 30),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          ScaleText(
            textDelegate.unableToAccessAll,
            style: const TextStyle(fontSize: 22),
            textAlign: TextAlign.center,
            semanticsLabel: semanticsTextDelegate.unableToAccessAll,
          ),
          SizedBox(height: size.height / 30),
          ScaleText(
            textDelegate.accessAllTip,
            style: const TextStyle(fontSize: 18),
            textAlign: TextAlign.center,
            semanticsLabel: semanticsTextDelegate.accessAllTip,
          ),
        ],
      ),
    );

    final Widget goToSettingsButton = MaterialButton(
      elevation: 0,
      minWidth: size.width / 2,
      height: appBarItemHeight * 1.25,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      color: themeColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(5),
      ),
      onPressed: PhotoManager.openSetting,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      child: ScaleText(
        textDelegate.goToSystemSettings,
        style: const TextStyle(fontSize: 17),
        semanticsLabel: semanticsTextDelegate.goToSystemSettings,
      ),
    );

    final Widget accessLimitedButton = GestureDetector(
      onTap: () {
        permissionOverlayDisplay.value = false;
      },
      child: ScaleText(
        textDelegate.accessLimitedAssets,
        style: TextStyle(color: interactiveTextColor(context)),
        semanticsLabel: semanticsTextDelegate.accessLimitedAssets,
      ),
    );

    return ValueListenableBuilder2<PermissionState, bool>(
      firstNotifier: permissionNotifier,
      secondNotifier: permissionOverlayDisplay,
      builder: (_, PermissionState ps, bool isDisplay, __) {
        if (ps.isAuth || !isDisplay) {
          return const SizedBox.shrink();
        }
        return Positioned.fill(
          child: Semantics(
            sortKey: const OrdinalSortKey(0),
            child: Container(
              padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
              color: context.theme.canvasColor,
              child: Column(
                children: <Widget>[
                  closeButton,
                  Expanded(child: limitedTips),
                  goToSettingsButton,
                  SizedBox(height: size.height / 18),
                  accessLimitedButton,
                  SizedBox(
                    height: math.max(
                      MediaQuery.paddingOf(context).bottom,
                      24.0,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class DefaultAssetPickerBuilderDelegate
    extends AssetPickerBuilderDelegate<AssetEntity, AssetPathEntity> {
  DefaultAssetPickerBuilderDelegate({
    required this.provider,
    required super.initialPermission,
    super.gridCount,
    super.pickerTheme,
    super.specialItemPosition,
    super.specialItemBuilder,
    super.loadingIndicatorBuilder,
    super.selectPredicate,
    super.shouldRevertGrid,
    super.limitedPermissionOverlayPredicate,
    super.pathNameBuilder,
    super.assetsChangeCallback,
    super.assetsChangeRefreshPredicate,
    super.themeColor,
    super.textDelegate,
    super.locale,
    super.isPrivateMode,
    this.gridThumbnailSize = defaultAssetGridPreviewSize,
    this.previewThumbnailSize,
    this.specialPickerType,
    this.keepScrollOffset = false,
    this.shouldAutoplayPreview = false,
  }) {
    // Add the listener if [keepScrollOffset] is true.
    if (keepScrollOffset) {
      gridScrollController.addListener(keepScrollOffsetListener);
    }
  }

  /// [ChangeNotifier] for asset picker.
  /// 资源选择器状态保持
  final DefaultAssetPickerProvider provider;

  /// Thumbnail size in the grid.
  /// 预览时网络的缩略图大小
  ///
  /// This only works on images and videos since other types does not have to
  /// request for the thumbnail data. The preview can speed up by reducing it.
  /// 该参数仅生效于图片和视频类型的资源，因为其他资源不需要请求缩略图数据。
  /// 预览图片的速度可以通过适当降低它的数值来提升。
  ///
  /// This cannot be `null` or a large value since you shouldn't use the
  /// original data for the grid.
  /// 该值不能为空或者非常大，因为在网格中使用原数据不是一个好的决定。
  final ThumbnailSize gridThumbnailSize;

  /// Preview thumbnail size in the viewer.
  /// 预览时图片的缩略图大小
  ///
  /// This only works on images and videos since other types does not have to
  /// request for the thumbnail data. The preview can speed up by reducing it.
  /// 该参数仅生效于图片和视频类型的资源，因为其他资源不需要请求缩略图数据。
  /// 预览图片的速度可以通过适当降低它的数值来提升。
  ///
  /// Default is `null`, which will request the origin data.
  /// 默认为空，即读取原图。
  final ThumbnailSize? previewThumbnailSize;

  /// The current special picker type for the picker.
  /// 当前特殊选择类型
  ///
  /// Several types which are special:
  /// * [SpecialPickerType.wechatMoment] When user selected video, no more images
  /// can be selected.
  /// * [SpecialPickerType.noPreview] Disable preview of asset; Clicking on an
  /// asset selects it.
  ///
  /// 这里包含一些特殊选择类型：
  /// * [SpecialPickerType.wechatMoment] 微信朋友圈模式。当用户选择了视频，将不能选择图片。
  /// * [SpecialPickerType.noPreview] 禁用资源预览。多选时单击资产将直接选中，单选时选中并返回。
  final SpecialPickerType? specialPickerType;

  /// Whether the picker should save the scroll offset between pushes and pops.
  /// 选择器是否可以从同样的位置开始选择
  final bool keepScrollOffset;

  /// Whether the preview should auto play.
  /// 预览是否自动播放
  final bool shouldAutoplayPreview;

  /// [Duration] when triggering path switching.
  /// 切换路径时的动画时长
  Duration get switchingPathDuration => Duration.zero;

  /// [Curve] when triggering path switching.
  /// 切换路径时的动画曲线
  Curve get switchingPathCurve => Curves.easeInOutQuad;

  /// Whether the [SpecialPickerType.wechatMoment] is enabled.
  /// 当前是否为微信朋友圈选择模式
  bool get isWeChatMoment =>
      specialPickerType == SpecialPickerType.wechatMoment;

  /// Whether the preview of assets is enabled.
  /// 资源的预览是否启用
  bool get isPreviewEnabled => specialPickerType != SpecialPickerType.noPreview;

  @override
  bool get isSingleAssetMode => provider.maxAssets == 1;

  /// The listener to track the scroll position of the [gridScrollController]
  /// if [keepScrollOffset] is true.
  /// 当 [keepScrollOffset] 为 true 时，跟踪 [gridScrollController] 位置的监听。
  void keepScrollOffsetListener() {
    if (gridScrollController.hasClients) {
      Singleton.scrollPosition = gridScrollController.position;
    }
  }

  /// Be aware that the method will do nothing when [keepScrollOffset] is true.
  /// 注意当 [keepScrollOffset] 为 true 时方法不会进行释放。
  @override
  void dispose() {
    // Skip delegate's dispose when it's keeping scroll offset.
    if (keepScrollOffset) {
      return;
    }
    provider.dispose();
    super.dispose();
  }

  @override
  Future<void> selectAsset(
    BuildContext context,
    AssetEntity asset,
    int index,
    bool selected,
    bool isMultipleSelection,
  ) async {
    final DefaultAssetPickerProvider provider =
        context.read<DefaultAssetPickerProvider>();

    final bool? selectPredicateResult = await selectPredicate?.call(
      context,
      asset,
      selected,
    );
    if (selectPredicateResult == false) {
      return;
    }
    if (selected) {
      provider.unSelectAsset(asset);
      return;
    }
    if (false == isMultipleSelection) {
      provider.selectedAssets.clear();
    }
    final AssetEntity entity = asset;
    final file = await entity.file;
    if ((entity.width >= 10000 && (entity.width / entity.height) > 3) ||
        (entity.height >= 10000 && (entity.height / entity.width) > 3)) {
      // 이미지 길이 또는 높이가 10000 이상이고 비율이 3보다 큰 이미지인 경우 toast message 노출
      AssetToast.show(
        context,
        message: Singleton
            .textDelegate.semanticsTextDelegate.sOverImageRateToastMessage,
      );
      return;
    }
    try {
      int size = 0;
      if (Platform.isAndroid) {
        size = file?.readAsBytesSync().length ?? 0;
      } else {
        size = (await entity.originBytes)?.length ?? 0;
      }
      if ((size / 1000000).roundToDouble() >= 200) {
        // 200 MB 이상의 파일이 1개라도 있는 경우 1회 toast message 노출
        AssetToast.show(
          context,
          message: Singleton
              .textDelegate.semanticsTextDelegate.sOver200MBToastMessage,
        );
      } else {
        provider.selectAsset(asset);
      }
    } catch (e) {
      print('Exception : ${e.toString()}');
      AssetToast.show(
        context,
        message:
            Singleton.textDelegate.semanticsTextDelegate.sOver200MBToastMessage,
      );
    }
  }

  @override
  Future<void> onAssetsChanged(MethodCall call, StateSetter setState) async {
    final permission = permissionNotifier.value;

    bool predicate() {
      final path = provider.currentPath?.path;
      if (assetsChangeRefreshPredicate != null) {
        return assetsChangeRefreshPredicate!(permission, call, path);
      }
      return path?.isAll == true;
    }

    if (!predicate()) {
      return;
    }

    assetsChangeCallback?.call(permission, call, provider.currentPath?.path);

    final createIds = <String>[];
    final updateIds = <String>[];
    final deleteIds = <String>[];
    int newCount = 0;
    int oldCount = 0;

    // Typically for iOS.
    if (call.arguments case final Map arguments) {
      if (arguments['newCount'] case final int count) {
        newCount = count;
      }
      if (arguments['oldCount'] case final int count) {
        oldCount = count;
      }
      for (final e in (arguments['create'] as List?) ?? []) {
        if (e['id'] case final String id) {
          createIds.add(id);
        }
      }
      for (final e in (arguments['update'] as List?) ?? []) {
        if (e['id'] case final String id) {
          updateIds.add(id);
        }
      }
      for (final e in (arguments['delete'] as List?) ?? []) {
        if (e['id'] case final String id) {
          deleteIds.add(id);
        }
      }
      if (createIds.isEmpty &&
          updateIds.isEmpty &&
          deleteIds.isEmpty &&
          // Updates with limited permission on iOS does not provide any IDs.
          // Counting on length changes is not reliable.
          (newCount == oldCount && permission != PermissionState.limited)) {
        return;
      }
    }
    // Throttle handling.
    if (onAssetsChangedLock case final lock?) {
      return lock.future;
    }
    final lock = Completer<void>();
    onAssetsChangedLock = lock;

    Future<void>(() async {
      // Replace the updated assets if update only.
      if (updateIds.isNotEmpty && createIds.isEmpty && deleteIds.isEmpty) {
        await Future.wait(
          updateIds.map((id) async {
            final i = provider.currentAssets.indexWhere((e) => e.id == id);
            if (i != -1) {
              final asset =
                  await provider.currentAssets[i].obtainForNewProperties();
              provider.currentAssets[i] = asset!;
            }
          }),
        );
        return;
      }

      await provider.getPaths(keepPreviousCount: true);
      provider.currentPath = provider.paths.first;
      final currentWrapper = provider.currentPath;
      if (currentWrapper != null) {
        final newPath = await currentWrapper.path.obtainForNewProperties();
        final assetCount = await newPath.assetCountAsync;
        final newPathWrapper = PathWrapper<AssetPathEntity>(
          path: newPath,
          assetCount: assetCount,
        );
        if (newPath.isAll) {
          await provider.getAssetsFromCurrentPath();
          final entitiesShouldBeRemoved = <AssetEntity>[];
          for (final entity in provider.selectedAssets) {
            if (!provider.currentAssets.contains(entity)) {
              entitiesShouldBeRemoved.add(entity);
            }
          }
          entitiesShouldBeRemoved.forEach(provider.selectedAssets.remove);
        }
        provider
          ..currentPath = newPathWrapper
          ..hasAssetsToDisplay = assetCount != 0
          ..isAssetsEmpty = assetCount == 0
          ..totalAssetsCount = assetCount
          ..getThumbnailFromPath(newPathWrapper);
      }
      isSwitchingPath.value = false;
    }).then(lock.complete).catchError(lock.completeError).whenComplete(() {
      onAssetsChangedLock = null;
    });
  }

  @override
  Future<void> viewAsset(
    BuildContext context,
    int? index,
    List<AssetEntity>? currentAssets,
    AssetEntity currentAsset,
  ) async {
    final p = context.read<DefaultAssetPickerProvider>();
    // - When we reached the maximum select count and the asset is not selected,
    //   do nothing.
    // - When the special type is WeChat Moment, pictures and videos cannot
    //   be selected at the same time. Video select should be banned if any
    //   pictures are selected.
    if ((!p.selectedAssets.contains(currentAsset) && p.selectedMaximumAssets) ||
        (isWeChatMoment &&
            currentAsset.type == AssetType.video &&
            p.selectedAssets.isNotEmpty)) {
      return;
    }
    final revert = effectiveShouldRevertGrid(context);
    List<AssetEntity> current;
    final List<AssetEntity>? selected;
    final int effectiveIndex;
    if (isWeChatMoment) {
      if (currentAsset.type == AssetType.video) {
        current = <AssetEntity>[currentAsset];
        selected = null;
        effectiveIndex = 0;
      } else {
        if (index == null) {
          current = p.selectedAssets;
          current = current.reversed.toList(growable: false);
        } else {
          current = currentAssets ?? p.currentAssets;
        }
        current = current
            .where((AssetEntity e) => e.type == AssetType.image)
            .toList();
        selected = p.selectedAssets;
        final i = current.indexOf(currentAsset);
        effectiveIndex = revert ? current.length - i - 1 : i;
      }
    } else {
      selected = p.selectedAssets;
      if (index == null) {
        current = p.selectedAssets;
        if (revert) {
          current = current.reversed.toList(growable: false);
        }
        effectiveIndex = selected.indexOf(currentAsset);
      } else {
        current = currentAssets ?? p.currentAssets;
        effectiveIndex = revert ? current.length - index - 1 : index;
      }
    }
    final List<AssetEntity>? result = await AssetPickerViewer.pushToViewer(
      context,
      currentIndex: effectiveIndex,
      previewAssets: current,
      themeData: theme,
      previewThumbnailSize: previewThumbnailSize,
      selectPredicate: selectPredicate,
      selectedAssets: selected,
      selectorProvider: p,
      specialPickerType: specialPickerType,
      maxAssets: p.maxAssets,
      shouldReversePreview: revert,
      shouldAutoplayPreview: shouldAutoplayPreview,
      isPrivateMode: isPrivateMode,
    );
    if (result != null) {
      Navigator.maybeOf(context)?.maybePop(result);
    }
  }

  @override
  AssetPickerAppBar appBar(BuildContext context) {
    final AssetPickerAppBar appBar = AssetPickerAppBar(
      backgroundColor: const Color.fromRGBO(44, 44, 44, 1),
      title: Semantics(
        onTapHint: semanticsTextDelegate.sActionSwitchPathLabel,
        child: pathEntitySelector(context),
      ),
      leading: backButton(context),
      blurRadius: isAppleOS(context) ? appleOSBlurRadius : 0,
    );
    appBarPreferredSize ??= appBar.preferredSize;
    return appBar;
  }

  @override
  Widget androidLayout(BuildContext context, bool isMultipleSelection) {
    return AssetPickerAppBarWrapper(
      appBar: appBar(context),
      body: Consumer<DefaultAssetPickerProvider>(
        builder: (BuildContext context, DefaultAssetPickerProvider p, _) {
          final bool shouldDisplayAssets =
              p.hasAssetsToDisplay || shouldBuildSpecialItem;
          return AnimatedSwitcher(
            duration: switchingPathDuration,
            child: shouldDisplayAssets
                ? Stack(
                    children: <Widget>[
                      RepaintBoundary(
                        child: Column(
                          children: <Widget>[
                            Expanded(
                              child: assetsGridBuilder(
                                context,
                                isMultipleSelection,
                                '',
                              ),
                            ),
                            if (isPreviewEnabled || !isSingleAssetMode)
                              bottomActionBar(context),
                          ],
                        ),
                      ),
                      pathEntityListBackdrop(context),
                      pathEntityListWidget(context),
                    ],
                  )
                : loadingIndicator(context),
          );
        },
      ),
    );
  }

  @override
  Widget appleOSLayout(BuildContext context, bool isMultipleSelection) {
    Widget gridLayout(BuildContext context) {
      return ValueListenableBuilder<bool>(
        valueListenable: isSwitchingPath,
        builder: (_, bool isSwitchingPath, __) => Semantics(
          excludeSemantics: isSwitchingPath,
          child: RepaintBoundary(
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: assetsGridBuilder(
                    context,
                    isMultipleSelection,
                    '',
                  ),
                ),
                if (isPreviewEnabled || !isSingleAssetMode)
                  Positioned.fill(top: null, child: bottomActionBar(context)),
              ],
            ),
          ),
        ),
      );
    }

    Widget layout(BuildContext context) {
      return Stack(
        children: <Widget>[
          Positioned.fill(
            child: Consumer<DefaultAssetPickerProvider>(
              builder: (_, DefaultAssetPickerProvider p, __) {
                final Widget child;
                final bool shouldDisplayAssets =
                    p.hasAssetsToDisplay || shouldBuildSpecialItem;
                if (shouldDisplayAssets) {
                  child = Stack(
                    children: <Widget>[
                      gridLayout(context),
                      pathEntityListBackdrop(context),
                      pathEntityListWidget(context),
                    ],
                  );
                } else {
                  child = loadingIndicator(context);
                }
                return AnimatedSwitcher(
                  duration: switchingPathDuration,
                  child: child,
                );
              },
            ),
          ),
          appBar(context),
        ],
      );
    }

    return ValueListenableBuilder<bool>(
      valueListenable: permissionOverlayDisplay,
      builder: (_, bool value, Widget? child) {
        if (value) {
          return ExcludeSemantics(child: child);
        }
        return child!;
      },
      child: layout(context),
    );
  }

  @override
  Widget loadingIndicator(BuildContext context) {
    return Selector<DefaultAssetPickerProvider, bool>(
      selector: (_, DefaultAssetPickerProvider p) => p.isAssetsEmpty,
      builder: (BuildContext context, bool isAssetsEmpty, Widget? w) {
        if (loadingIndicatorBuilder != null) {
          return loadingIndicatorBuilder!(context, isAssetsEmpty);
        }
        return Center(child: isAssetsEmpty ? emptyIndicator(context) : w);
      },
      child: PlatformProgressIndicator(
        color: theme.iconTheme.color,
        size: MediaQuery.sizeOf(context).width / gridCount / 3,
      ),
    );
  }

  @override
  Widget assetsGridBuilder(
    BuildContext context,
    bool isMultipleSelection,
    String requestType,
  ) {
    appBarPreferredSize ??= appBar(context).preferredSize;
    final bool gridRevert = effectiveShouldRevertGrid(context);
    return Selector<DefaultAssetPickerProvider, PathWrapper<AssetPathEntity>?>(
      selector: (_, DefaultAssetPickerProvider p) => p.currentPath,
      builder: (
        BuildContext context,
        PathWrapper<AssetPathEntity>? wrapper,
        _,
      ) {
        int totalCount = wrapper?.assetCount ?? 0;
        final Widget? specialItem;
        if (specialItemPosition != SpecialItemPosition.none) {
          specialItem = specialItemBuilder?.call(
            context,
            wrapper?.path,
            totalCount,
          );
          if (specialItem != null) {
            totalCount += 1;
          }
        } else {
          specialItem = null;
        }
        if (totalCount == 0 && specialItem == null) {
          return loadingIndicator(context);
        }

        final int placeholderCount;
        if (gridRevert && totalCount % gridCount != 0) {
          placeholderCount = gridCount - totalCount % gridCount;
        } else {
          placeholderCount = 0;
        }

        final int row = (totalCount + placeholderCount) ~/ gridCount;
        final double dividedSpacing = itemSpacing / gridCount;
        final double topPadding =
            context.topPadding + appBarPreferredSize!.height;

        Widget sliverGrid(BuildContext context, List<AssetEntity> assets) {
          return SliverGrid(
            delegate: SliverChildBuilderDelegate(
              (_, int index) => Builder(
                builder: (BuildContext context) {
                  if (gridRevert) {
                    if (index < placeholderCount) {
                      return const SizedBox.shrink();
                    }
                    index -= placeholderCount;
                  }
                  return MergeSemantics(
                    child: Directionality(
                      textDirection: Directionality.of(context),
                      child: assetGridItemBuilder(
                        context,
                        index,
                        assets,
                        isMultipleSelection,
                        specialItem: specialItem,
                      ),
                    ),
                  );
                },
              ),
              childCount: assetsGridItemCount(
                context: context,
                assets: assets,
                placeholderCount: placeholderCount,
                specialItem: specialItem,
              ),
              findChildIndexCallback: (Key? key) {
                if (key is ValueKey<String>) {
                  return findChildIndexBuilder(
                    id: key.value,
                    assets: assets,
                    placeholderCount: placeholderCount,
                  );
                }
                return null;
              },
              addSemanticIndexes: false,
            ),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: gridCount,
              mainAxisSpacing: itemSpacing,
              crossAxisSpacing: itemSpacing,
            ),
          );
        }

        return LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double itemSize = constraints.maxWidth / gridCount;
            final bool onlyOneScreen = row * itemSize <=
                constraints.maxHeight -
                    context.bottomPadding -
                    topPadding -
                    permissionLimitedBarHeight;
            final double height;
            if (onlyOneScreen) {
              height = constraints.maxHeight;
            } else {
              height = constraints.maxHeight - permissionLimitedBarHeight;
            }

            final double anchor = math.min(
              (row * (itemSize + dividedSpacing) + topPadding - itemSpacing) /
                  height,
              1,
            );

            return Directionality(
              textDirection: effectiveGridDirection(context),
              child: Container(
                color: Colors.white,
                child: Selector<DefaultAssetPickerProvider, List<AssetEntity>>(
                  selector: (_, DefaultAssetPickerProvider p) =>
                      p.currentAssets,
                  builder: (BuildContext context, List<AssetEntity> assets, _) {
                    List<AssetEntity> typeAssets = [];
                    if (requestType == 'image') {
                      typeAssets = assets
                          .where((asset) => asset.type == AssetType.image)
                          .toList();
                    } else if (requestType == 'video') {
                      typeAssets = assets
                          .where((asset) => asset.type == AssetType.video)
                          .toList();
                    } else {
                      typeAssets = List.from(assets);
                    }
                    final SliverGap bottomGap = SliverGap.v(
                      context.bottomPadding + bottomSectionHeight,
                    );
                    appBarPreferredSize ??= appBar(context).preferredSize;
                    return CustomScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      controller: gridScrollController,
                      anchor: gridRevert ? anchor : 0,
                      center: gridRevert ? gridRevertKey : null,
                      slivers: [
                        sliverGrid(context, typeAssets),
                        if (gridRevert && anchor == 1) bottomGap,
                        if (gridRevert)
                          SliverToBoxAdapter(
                            key: gridRevertKey,
                            child: const SizedBox.shrink(),
                          ),
                        if (isAppleOS(context) && !gridRevert) bottomGap,
                      ],
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  /// There are several conditions within this builder:
  ///  * Return item builder according to the asset's type.
  ///    * [AssetType.audio] -> [audioItemBuilder]
  ///    * [AssetType.image], [AssetType.video] -> [imageAndVideoItemBuilder]
  ///  * Load more assets when the index reached at third line counting
  ///    backwards.
  ///
  /// 资源构建有几个条件：
  ///  * 根据资源类型返回对应类型的构建：
  ///    * [AssetType.audio] -> [audioItemBuilder] 音频类型
  ///    * [AssetType.image], [AssetType.video] -> [imageAndVideoItemBuilder]
  ///      图片和视频类型
  ///  * 在索引到达倒数第三列的时候加载更多资源。
  @override
  Widget assetGridItemBuilder(
    BuildContext context,
    int index,
    List<AssetEntity> currentAssets,
    bool isMultipleSelection, {
    Widget? specialItem,
  }) {
    final DefaultAssetPickerProvider p =
        context.read<DefaultAssetPickerProvider>();
    final int length = currentAssets.length;
    final PathWrapper<AssetPathEntity>? currentWrapper = p.currentPath;
    final AssetPathEntity? currentPathEntity = currentWrapper?.path;

    if (specialItem != null) {
      if ((index == 0 && specialItemPosition == SpecialItemPosition.prepend) ||
          (index == length &&
              specialItemPosition == SpecialItemPosition.append)) {
        return specialItem;
      }
    }

    final int currentIndex;
    if (specialItem != null &&
        specialItemPosition == SpecialItemPosition.prepend) {
      currentIndex = index - 1;
    } else {
      currentIndex = index;
    }

    if (currentPathEntity == null) {
      return const SizedBox.shrink();
    }

    if (p.hasMoreToLoad) {
      if ((p.pageSize <= gridCount * 3 && index == length - 1) ||
          index == length - gridCount * 3) {
        p.loadMoreAssets();
      }
    }

    final AssetEntity asset =
        resizeAsset(currentAssets.elementAt(currentIndex));
    final Widget builder = switch (asset.type) {
      AssetType.image ||
      AssetType.video =>
        imageAndVideoItemBuilder(context, currentIndex, asset),
      AssetType.audio => audioItemBuilder(context, currentIndex, asset),
      AssetType.other => const SizedBox.shrink(),
    };
    final Widget content = Stack(
      key: ValueKey<String>(asset.id),
      children: <Widget>[
        builder,
        selectedBackdrop(
          context,
          currentAssets,
          currentIndex,
          asset,
          isMultipleSelection,
        ),
        if (!isWeChatMoment || asset.type != AssetType.video)
          selectIndicator(context, index, asset, isMultipleSelection),
        if (isMultipleSelection) itemBannedIndicator(context, asset),
      ],
    );
    return assetGridItemSemanticsBuilder(
      context,
      index,
      asset,
      isMultipleSelection,
      content,
    );
  }

  int semanticIndex(int index) {
    if (specialItemPosition != SpecialItemPosition.prepend) {
      return index + 1;
    }
    return index;
  }

  AssetEntity resizeAsset(AssetEntity asset) {
    AssetEntity resizeAsset = asset;
    int width = asset.width;
    int height = asset.height;
    if (width > height) {
      // 가로 사진
      if (width > 1280) {
        width = 1280;
        height = (width * (asset.height / asset.width)).round();
      }
    } else if (width < height) {
      // 세로 사진
      if (height > 1280) {
        height = 1280;
        width = (height * (asset.width / asset.height)).round();
      }
    } else {
      // 정사각형 사진
      if (height > 1280 && width > 1280) {
        width = 1280;
        height = 1280;
      }
    }
    resizeAsset = asset.copyWith(
      width: width,
      height: height,
    );
    return resizeAsset;
  }

  @override
  Widget assetGridItemSemanticsBuilder(
    BuildContext context,
    int index,
    AssetEntity asset,
    bool isMultipleSelection,
    Widget child,
  ) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSwitchingPath,
      builder: (_, bool isSwitchingPath, Widget? child) {
        return Consumer<DefaultAssetPickerProvider>(
          builder: (_, DefaultAssetPickerProvider p, __) {
            final bool isBanned = (!p.selectedAssets.contains(asset) &&
                    p.selectedMaximumAssets) ||
                (isWeChatMoment &&
                    asset.type == AssetType.video &&
                    p.selectedAssets.isNotEmpty);
            final bool isSelected = p.selectedDescriptions.contains(
              asset.toString(),
            );
            final int selectedIndex = p.selectedAssets.indexOf(asset) + 1;
            String hint = '';
            if (asset.type == AssetType.audio ||
                asset.type == AssetType.video) {
              hint += '${semanticsTextDelegate.sNameDurationLabel}: ';
              hint += semanticsTextDelegate.durationIndicatorBuilder(
                asset.videoDuration,
              );
            }
            if (asset.title?.isNotEmpty ?? false) {
              hint += ', ${asset.title}';
            }
            return Semantics(
              button: false,
              enabled: !isBanned,
              excludeSemantics: true,
              focusable: !isSwitchingPath,
              label: '${semanticsTextDelegate.semanticTypeLabel(asset.type)}'
                  '${semanticIndex(index)}, '
                  '${asset.createDateTime.toString().replaceAll('.000', '')}',
              hidden: isSwitchingPath,
              hint: hint,
              image: asset.type == AssetType.image ||
                  asset.type == AssetType.video,
              onTap: () {
                selectAsset(
                  context,
                  asset,
                  index,
                  isSelected,
                  isMultipleSelection,
                );
              },
              onTapHint: semanticsTextDelegate.sActionSelectHint,
              onLongPress: isPreviewEnabled
                  ? () {
                      viewAsset(context, index, null, asset);
                    }
                  : null,
              onLongPressHint: semanticsTextDelegate.sActionPreviewHint,
              selected: isSelected,
              sortKey: OrdinalSortKey(
                semanticIndex(index).toDouble(),
                name: 'GridItem',
              ),
              value: selectedIndex > 0 ? '$selectedIndex' : null,
              child: GestureDetector(
                // Regression https://github.com/flutter/flutter/issues/35112.
                onLongPress: isPreviewEnabled &&
                        MediaQuery.accessibleNavigationOf(context)
                    ? () {
                        viewAsset(context, index, null, asset);
                      }
                    : null,
                child: IndexedSemantics(
                  index: semanticIndex(index),
                  child: child,
                ),
              ),
            );
          },
        );
      },
      child: child,
    );
  }

  @override
  int findChildIndexBuilder({
    required String id,
    required List<AssetEntity> assets,
    int placeholderCount = 0,
  }) {
    int index = assets.indexWhere((AssetEntity e) => e.id == id);
    if (specialItemPosition == SpecialItemPosition.prepend) {
      index += 1;
    }
    index += placeholderCount;
    return index;
  }

  @override
  int assetsGridItemCount({
    required BuildContext context,
    required List<AssetEntity> assets,
    int placeholderCount = 0,
    Widget? specialItem,
  }) {
    final PathWrapper<AssetPathEntity>? currentWrapper = context
        .select<DefaultAssetPickerProvider, PathWrapper<AssetPathEntity>?>(
      (DefaultAssetPickerProvider p) => p.currentPath,
    );
    final AssetPathEntity? currentPathEntity = currentWrapper?.path;
    final int length = assets.length + placeholderCount;

    // Return 1 if the [specialItem] build something.
    if (currentPathEntity == null && specialItem != null) {
      return placeholderCount + 1;
    }

    // Return actual length if the current path is all.
    // 如果当前目录是全部内容，则返回实际的内容数量。
    if (currentPathEntity?.isAll != true && specialItem == null) {
      return length;
    }
    return switch (specialItemPosition) {
      SpecialItemPosition.none => length,
      SpecialItemPosition.prepend || SpecialItemPosition.append => length + 1,
    };
  }

  @override
  Widget audioIndicator(BuildContext context, AssetEntity asset) {
    return Container(
      width: double.maxFinite,
      alignment: AlignmentDirectional.bottomStart,
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: AlignmentDirectional.bottomCenter,
          end: AlignmentDirectional.topCenter,
          colors: <Color>[theme.splashColor, Colors.transparent],
        ),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: 4),
        child: ScaleText(
          textDelegate.durationIndicatorBuilder(
            Duration(seconds: asset.duration),
          ),
          style: const TextStyle(fontSize: 16),
          semanticsLabel: '${semanticsTextDelegate.sNameDurationLabel}: '
              '${semanticsTextDelegate.durationIndicatorBuilder(
            Duration(seconds: asset.duration),
          )}',
        ),
      ),
    );
  }

  @override
  Widget audioItemBuilder(BuildContext context, int index, AssetEntity asset) {
    return Stack(
      children: <Widget>[
        Container(
          width: double.maxFinite,
          alignment: AlignmentDirectional.topStart,
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: AlignmentDirectional.topCenter,
              end: AlignmentDirectional.bottomCenter,
              colors: <Color>[theme.splashColor, Colors.transparent],
            ),
          ),
          child: Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, end: 30),
            child: ScaleText(
              asset.title ?? '',
              style: const TextStyle(fontSize: 16),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
        const Align(
          alignment: AlignmentDirectional(0.9, 0.8),
          child: Icon(Icons.audiotrack),
        ),
        audioIndicator(context, asset),
      ],
    );
  }

  /// It'll pop with [AssetPickerProvider.selectedAssets]
  /// when there are any assets were chosen.
  /// 当有资源已选时，点击按钮将把已选资源通过路由返回。
  @override
  Widget confirmButton(BuildContext context) {
    final Widget button = Consumer<DefaultAssetPickerProvider>(
      builder: (_, DefaultAssetPickerProvider p, __) {
        final active = p.selectedAssets.isNotEmpty;
        return Container(
          alignment: Alignment.center,
          margin: const EdgeInsets.only(right: 12.0),
          child: InkWell(
            onTap: () async {
              if (!active) {
                return;
              }

              Navigator.maybeOf(context)?.maybePop(p.selectedAssets);
            },
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                Singleton.textDelegate.semanticsTextDelegate.sDoneButtonText,
                style: const TextStyle(
                  fontSize: 18.0,
                  fontWeight: FontWeight.w400,
                ).copyWith(
                  color: isPrivateMode && active
                      ? const Color.fromRGBO(230, 230, 230, 1)
                      : isPrivateMode && false == active
                          ? const Color.fromRGBO(99, 106, 121, 1)
                          : false == isPrivateMode && active
                              ? const Color.fromRGBO(121, 64, 255, 1)
                              : const Color.fromRGBO(230, 230, 230, 1),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        );
      },
    );

    return ChangeNotifierProvider<DefaultAssetPickerProvider>.value(
      value: provider,
      builder: (_, __) => button,
    );
  }

  @override
  Widget imageAndVideoItemBuilder(
    BuildContext context,
    int index,
    AssetEntity asset,
  ) {
    return LocallyAvailableBuilder(
      asset: asset,
      builder: (context, asset) {
        final imageProvider = AssetEntityImageProvider(
          asset,
          isOriginal: false,
          thumbnailSize: gridThumbnailSize,
        );
        SpecialImageType? type;
        if (imageProvider.imageFileType == ImageFileType.gif) {
          type = SpecialImageType.gif;
        } else if (imageProvider.imageFileType == ImageFileType.heic) {
          type = SpecialImageType.heic;
        }
        return Stack(
          children: <Widget>[
            Positioned.fill(
              child: RepaintBoundary(
                child: AssetEntityGridItemBuilder(
                  image: imageProvider,
                  failedItemBuilder: failedItemBuilder,
                ),
              ),
            ),
            if (type == SpecialImageType.gif) // 如果为GIF则显示标识
              gifIndicator(context, asset),
            if (asset.type == AssetType.video) // 如果为视频则显示标识
              videoIndicator(context, asset),
          ],
        );
      },
      progressBuilder: (context, state, progress) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            state == PMRequestState.failed
                ? Icons.cloud_off
                : Icons.cloud_download_outlined,
            color: context.iconTheme.color?.withOpacity(.4),
            size: 24.0,
          ),
          if (state != PMRequestState.success && state != PMRequestState.failed)
            ScaleText(
              ' ${((progress ?? 0) * 100).toInt()}%',
              style: TextStyle(
                color: context.textTheme.bodyMedium?.color?.withOpacity(.4),
                fontSize: 12.0,
              ),
            ),
        ],
      ),
    );
  }

  /// While the picker is switching path, this will displayed.
  /// If the user tapped on it, it'll collapse the list widget.
  ///
  /// 当选择器正在选择路径时，它会出现。用户点击它时，列表会折叠收起。
  @override
  Widget pathEntityListBackdrop(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: isSwitchingPath,
      builder: (_, bool isSwitchingPath, __) => Positioned.fill(
        child: IgnorePointer(
          ignoring: !isSwitchingPath,
          child: ExcludeSemantics(
            child: GestureDetector(
              onTap: () {
                this.isSwitchingPath.value = false;
              },
              child: AnimatedOpacity(
                duration: switchingPathDuration,
                opacity: isSwitchingPath ? .75 : 0,
                child: const ColoredBox(color: Colors.black),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget pathEntityListWidget(BuildContext context) {
    appBarPreferredSize ??= appBar(context).preferredSize;
    return Positioned(
      top: 0,
      left: 0.0,
      right: 0.0,
      child: ValueListenableBuilder<bool>(
        valueListenable: isSwitchingPath,
        builder: (_, bool isSwitchingPath, Widget? child) => Semantics(
          hidden: isSwitchingPath ? null : true,
          child: AnimatedAlign(
            duration: switchingPathDuration,
            curve: switchingPathCurve,
            alignment: Alignment.bottomCenter,
            heightFactor: isSwitchingPath ? 1 : 0,
            child: AnimatedOpacity(
              duration: switchingPathDuration,
              curve: switchingPathCurve,
              opacity: !isAppleOS(context) || isSwitchingPath ? 1 : 0,
              child: Container(
                color: Colors.transparent,
                child: child,
              ),
            ),
          ),
        ),
        child: Selector<DefaultAssetPickerProvider,
            List<PathWrapper<AssetPathEntity>>>(
          selector: (_, DefaultAssetPickerProvider p) => p.paths,
          builder: (_, List<PathWrapper<AssetPathEntity>> paths, __) {
            final List<PathWrapper<AssetPathEntity>> filtered = paths
                .where(
                  (PathWrapper<AssetPathEntity> p) => p.assetCount != 0,
                )
                .toList();

            return Container(
              width: double.infinity,
              color: isPrivateMode
                  ? const Color.fromRGBO(28, 30, 34, 1)
                  : Colors.white,
              child: SingleChildScrollView(
                controller: ScrollController(),
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    const SizedBox(
                      width: 12.0,
                    ),
                    ...filtered.map((filter) {
                      return pathEntityWidget(
                        context: context,
                        item: filter,
                      );
                    }),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget pathEntitySelector(BuildContext context) {
    Widget selector(BuildContext context) {
      return UnconstrainedBox(
        child: GestureDetector(
          onTap: () {
            Feedback.forTap(context);
            isSwitchingPath.value = !isSwitchingPath.value;
          },
          child: SizedBox(
            width: 200,
            height: appBarItemHeight,
            child: Selector<DefaultAssetPickerProvider,
                PathWrapper<AssetPathEntity>?>(
              selector: (_, DefaultAssetPickerProvider p) => p.currentPath,
              builder: (_, PathWrapper<AssetPathEntity>? p, Widget? w) {
                String name = '';
                if (p != null) {
                  name = p.path.name;
                  if (name == 'Recent') {
                    name = Singleton
                        .textDelegate.semanticsTextDelegate.sRecentName;
                  }
                }

                return Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (p != null)
                      Flexible(
                        child: Text(
                          name,
                          style: const TextStyle(
                            fontSize: 18.0,
                            fontWeight: FontWeight.normal,
                          ).copyWith(
                            color: isPrivateMode ? Colors.white : Colors.black,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    w!,
                  ],
                );
              },
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: 5),
                child: ValueListenableBuilder<bool>(
                  valueListenable: isSwitchingPath,
                  builder: (_, bool isSwitchingPath, Widget? w) {
                    return Transform.rotate(
                      angle: isSwitchingPath ? math.pi : 0,
                      child: w,
                    );
                  },
                  child: Icon(
                    Icons.arrow_drop_down_sharp,
                    size: 30.0,
                    color: isPrivateMode ? Colors.white : Colors.black,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    return ChangeNotifierProvider<DefaultAssetPickerProvider>.value(
      value: provider,
      builder: (BuildContext c, _) => selector(c),
    );
  }

  @override
  Widget pathEntityWidget({
    required BuildContext context,
    required PathWrapper<AssetPathEntity> item,
  }) {
    final PathWrapper<AssetPathEntity> wrapper = item;
    final AssetPathEntity pathEntity = wrapper.path;
    final Uint8List? data = wrapper.thumbnailData;

    Widget builder({required double size}) {
      if (data != null) {
        return Image.memory(
          data,
          height: size,
          width: size,
          fit: BoxFit.cover,
        );
      }
      if (pathEntity.type.containsAudio()) {
        return Container(
          height: size,
          width: size,
          color: theme.colorScheme.primary.withOpacity(0.12),
          child: const Center(
            child: Icon(Icons.audiotrack),
          ),
        );
      }
      return Container(
        height: size,
        width: size,
        color: theme.colorScheme.primary.withOpacity(0.12),
      );
    }

    final String pathName =
        pathNameBuilder?.call(pathEntity) ?? pathEntity.name;
    final String name = isPermissionLimited && pathEntity.isAll
        ? textDelegate.accessiblePathName
        : pathName;
    final String semanticsName = isPermissionLimited && pathEntity.isAll
        ? semanticsTextDelegate.accessiblePathName
        : pathName;
    final String? semanticsCount = wrapper.assetCount?.toString();
    final StringBuffer labelBuffer = StringBuffer(
      '$semanticsName, ${semanticsTextDelegate.sUnitAssetCountLabel}',
    );
    if (semanticsCount != null) {
      labelBuffer.write(': $semanticsCount');
    }
    return Selector<DefaultAssetPickerProvider, PathWrapper<AssetPathEntity>?>(
      selector: (_, DefaultAssetPickerProvider p) => p.currentPath,
      builder: (_, PathWrapper<AssetPathEntity>? currentWrapper, __) {
        final bool isSelected = currentWrapper?.path == pathEntity;
        String displayName = '';
        displayName = name;
        if (name == 'Recent') {
          displayName =
              Singleton.textDelegate.semanticsTextDelegate.sRecentName;
        }
        return Semantics(
          label: labelBuffer.toString(),
          selected: isSelected,
          onTapHint: semanticsTextDelegate.sActionSwitchPathLabel,
          button: false,
          child: GestureDetector(
            onTap: () {
              Feedback.forTap(context);
              context.read<DefaultAssetPickerProvider>().switchPath(wrapper);
              isSwitchingPath.value = false;
              gridScrollController.jumpTo(0);
            },
            child: Container(
              margin:
                  const EdgeInsets.only(right: 12.0, top: 10.0, bottom: 10.0),
              child: Stack(
                children: [
                  Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8.0),
                        child: builder(size: 72.0),
                      ),
                      const SizedBox(height: 8.0),
                      SizedBox(
                        width: 72.0,
                        child: Text(
                          displayName,
                          style: DefaultTextStyle.of(context).style.copyWith(
                                color:
                                    isPrivateMode ? Colors.white : Colors.black,
                              ),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget previewButton(BuildContext context) {
    return Consumer<DefaultAssetPickerProvider>(
      builder: (_, DefaultAssetPickerProvider p, Widget? child) {
        return ValueListenableBuilder<bool>(
          valueListenable: isSwitchingPath,
          builder: (_, bool isSwitchingPath, __) => Semantics(
            enabled: p.isSelectedNotEmpty,
            focusable: !isSwitchingPath,
            hidden: isSwitchingPath,
            onTapHint: semanticsTextDelegate.sActionPreviewHint,
            child: child,
          ),
        );
      },
      child: Consumer<DefaultAssetPickerProvider>(
        builder: (context, DefaultAssetPickerProvider p, __) => GestureDetector(
          onTap: p.isSelectedNotEmpty
              ? () {
                  viewAsset(context, null, null, p.selectedAssets.first);
                }
              : null,
          child: Selector<DefaultAssetPickerProvider, String>(
            selector: (_, DefaultAssetPickerProvider p) =>
                p.selectedDescriptions,
            builder: (BuildContext c, __, ___) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: ScaleText(
                '${textDelegate.preview}'
                '${p.isSelectedNotEmpty ? ' (${p.selectedAssets.length})' : ''}',
                style: TextStyle(
                  color: p.isSelectedNotEmpty
                      ? null
                      : c.textTheme.bodySmall?.color,
                  fontSize: 17,
                ),
                maxScaleFactor: 1.2,
                semanticsLabel: '${semanticsTextDelegate.preview}'
                    '${p.isSelectedNotEmpty ? ' (${p.selectedAssets.length})' : ''}',
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget itemBannedIndicator(BuildContext context, AssetEntity asset) {
    return Consumer<DefaultAssetPickerProvider>(
      builder: (_, DefaultAssetPickerProvider p, __) {
        final bool isDisabled =
            (!p.selectedAssets.contains(asset) && p.selectedMaximumAssets) ||
                (isWeChatMoment &&
                    asset.type == AssetType.video &&
                    p.selectedAssets.isNotEmpty);
        if (isDisabled) {
          return Container(
            color: theme.colorScheme.background.withOpacity(.85),
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  @override
  Widget selectIndicator(
    BuildContext context,
    int index,
    AssetEntity asset,
    bool isMultipleSelection,
  ) {
    final double indicatorSize =
        MediaQuery.sizeOf(context).width / gridCount / 3;
    final Duration duration = switchingPathDuration;
    return Selector<DefaultAssetPickerProvider, String>(
      selector: (_, DefaultAssetPickerProvider p) => p.selectedDescriptions,
      builder: (BuildContext context, String descriptions, __) {
        final DefaultAssetPickerProvider p =
            context.read<DefaultAssetPickerProvider>();
        final int assetIndex = p.selectedAssets.indexOf(asset);
        final bool selected = descriptions.contains(asset.toString());
        final Widget innerSelector = AnimatedContainer(
          duration: duration,
          width: indicatorSize / (isAppleOS(context) ? 1.25 : 1.5),
          height: indicatorSize / (isAppleOS(context) ? 1.25 : 1.5),
          padding: EdgeInsets.all(indicatorSize / 10),
          decoration: BoxDecoration(
            border: !selected
                ? Border.all(
                    color: const Color.fromRGBO(230, 230, 230, 1),
                    width: indicatorSize / 25,
                  )
                : null,
            color: isPrivateMode && selected
                ? const Color.fromRGBO(99, 106, 121, 1)
                : false == isPrivateMode && selected
                    ? const Color.fromRGBO(121, 64, 255, 1)
                    : null,
            shape: BoxShape.circle,
          ),
          child: FittedBox(
            child: AnimatedSwitcher(
              duration: duration,
              reverseDuration: duration,
              child: selected
                  ? isMultipleSelection
                      ? Text(
                          '${assetIndex + 1}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w500,
                            fontSize: 10,
                          ),
                        )
                      : const Icon(
                          Icons.check,
                          color: Colors.white,
                        )
                  : const SizedBox.shrink(),
            ),
          ),
        );
        final Widget selectorWidget = GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            selectAsset(
              context,
              asset,
              index,
              selected,
              isMultipleSelection,
            );
          },
          child: Container(
            margin: EdgeInsets.all(indicatorSize / 4),
            width: isPreviewEnabled ? indicatorSize : null,
            height: isPreviewEnabled ? indicatorSize : null,
            alignment: AlignmentDirectional.topEnd,
            child: (!isPreviewEnabled && isSingleAssetMode && !selected)
                ? const SizedBox.shrink()
                : innerSelector,
          ),
        );
        if (isPreviewEnabled) {
          return PositionedDirectional(
            top: 0,
            end: 0,
            child: selectorWidget,
          );
        }
        return selectorWidget;
      },
    );
  }

  @override
  Widget selectedBackdrop(
    BuildContext context,
    List<AssetEntity>? currentAssets,
    int index,
    AssetEntity asset,
    bool isMultipleSelection,
  ) {
    final double indicatorSize =
        MediaQuery.sizeOf(context).width / gridCount / 3;
    return Positioned.fill(
      child: GestureDetector(
        onTap: isPreviewEnabled
            ? () {
                final DefaultAssetPickerProvider p =
                    context.read<DefaultAssetPickerProvider>();
                final selected = p.selectedAssets
                    .where((selectAssert) => selectAssert == asset)
                    .isNotEmpty;
                selectAsset(
                  context,
                  asset,
                  index,
                  selected,
                  isMultipleSelection,
                );
              }
            : null,
        child: Consumer<DefaultAssetPickerProvider>(
          builder: (_, DefaultAssetPickerProvider p, __) {
            final int index = p.selectedAssets.indexOf(asset);
            final bool selected = index != -1;
            return AnimatedContainer(
              duration: switchingPathDuration,
              padding: EdgeInsets.all(indicatorSize * .35),
              color: selected
                  ? const Color.fromRGBO(51, 51, 51, 0.3)
                  : Colors.transparent,
              child: const SizedBox.shrink(),
            );
          },
        ),
      ),
    );
  }

  /// Videos often contains various of color in the cover,
  /// so in order to keep the content visible in most cases,
  /// the color of the indicator has been set to [Colors.white].
  ///
  /// 视频封面通常包含各种颜色，为了保证内容在一般情况下可见，此处
  /// 将指示器的图标和文字设置为 [Colors.white]。
  @override
  Widget videoIndicator(BuildContext context, AssetEntity asset) {
    return PositionedDirectional(
      start: 0,
      end: 0,
      bottom: 0,
      child: Container(
        width: double.maxFinite,
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: AlignmentDirectional.bottomCenter,
            end: AlignmentDirectional.topCenter,
            colors: <Color>[theme.splashColor, Colors.transparent],
          ),
        ),
        child: Row(
          children: <Widget>[
            const Icon(Icons.videocam, size: 22, color: Colors.white),
            Expanded(
              child: Padding(
                padding: const EdgeInsetsDirectional.only(start: 4),
                child: ScaleText(
                  textDelegate.durationIndicatorBuilder(
                    Duration(seconds: asset.duration),
                  ),
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                  strutStyle: const StrutStyle(
                    forceStrutHeight: true,
                    height: 1.4,
                  ),
                  maxLines: 1,
                  maxScaleFactor: 1.2,
                  semanticsLabel:
                      semanticsTextDelegate.durationIndicatorBuilder(
                    Duration(seconds: asset.duration),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget bottomActionBar(BuildContext context) {
    Widget child = Container(
      height: bottomActionBarHeight + context.bottomPadding,
      padding: const EdgeInsets.symmetric(horizontal: 20).copyWith(
        bottom: context.bottomPadding,
      ),
      color: theme.bottomAppBarTheme.color?.withOpacity(
        theme.bottomAppBarTheme.color!.opacity * (isAppleOS(context) ? .9 : 1),
      ),
      child: Row(
        children: <Widget>[
          if (isPreviewEnabled) previewButton(context),
          if (isPreviewEnabled || !isSingleAssetMode) const Spacer(),
          if (isPreviewEnabled || !isSingleAssetMode) confirmButton(context),
        ],
      ),
    );
    if (isPermissionLimited) {
      child = Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[accessLimitedBottomTip(context), child],
      );
    }
    if (isAppleOS(context)) {
      child = ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: appleOSBlurRadius,
            sigmaY: appleOSBlurRadius,
          ),
          child: child,
        ),
      );
    }
    return child;
  }

  @override
  Widget build(BuildContext context) {
    // Schedule the scroll position's restoration callback if this feature
    // is enabled and offsets are different.
    if (keepScrollOffset && Singleton.scrollPosition != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Update only if the controller has clients.
        if (gridScrollController.hasClients) {
          gridScrollController.jumpTo(Singleton.scrollPosition!.pixels);
        }
      });
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Theme(
        data: theme,
        child: CNP<DefaultAssetPickerProvider>.value(
          value: provider,
          builder: (BuildContext context, _) => Material(
            color: theme.canvasColor,
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                if (isAppleOS(context))
                  appleOSLayout(context, true)
                else
                  androidLayout(context, true),
                permissionOverlay(context),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
