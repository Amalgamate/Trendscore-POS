import 'package:flutter/material.dart';
import '../theme/tokens.dart';

class SocialCommerceView extends StatelessWidget {
  const SocialCommerceView({super.key, this.onConnect});

  final ValueChanged<String>? onConnect;

  static const _channels = <_SocialChannel>[
    _SocialChannel(
      name: 'Facebook & Instagram',
      detail: 'Meta business accounts · product catalog and publishing',
      icon: Icons.groups_outlined,
      status: 'App review required',
    ),
    _SocialChannel(
      name: 'WhatsApp Business',
      detail: 'Official Cloud API · customer and order messaging',
      icon: Icons.chat_outlined,
      status: 'Business setup required',
    ),
    _SocialChannel(
      name: 'TikTok',
      detail: 'Video publishing · visibility depends on app audit',
      icon: Icons.music_video_outlined,
      status: 'Developer approval required',
    ),
    _SocialChannel(
      name: 'Threads',
      detail: 'Publishing and supported account insights',
      icon: Icons.forum_outlined,
      status: 'Account connection required',
    ),
    _SocialChannel(
      name: 'Pinterest',
      detail: 'Product pins and supported catalog features',
      icon: Icons.push_pin_outlined,
      status: 'Developer access required',
    ),
    _SocialChannel(
      name: 'YouTube',
      detail: 'Video publishing through an authorized channel',
      icon: Icons.play_circle_outline,
      status: 'OAuth setup required',
    ),
    _SocialChannel(
      name: 'X',
      detail: 'Post publishing through the official developer API',
      icon: Icons.alternate_email,
      status: 'Developer access required',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final narrow = MediaQuery.sizeOf(context).width < 760;
    return SingleChildScrollView(
      padding: EdgeInsets.all(narrow ? 16 : 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1180),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Publish products where your customers follow you.',
                style: TextStyle(
                  color: AppColors.text_primary,
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                'Each shop connects its own social accounts. Publishing is enabled only through official, approved platform APIs.',
                style: TextStyle(
                  color: AppColors.text_secondary,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              if (narrow)
                Column(
                  children: [
                    _composer(),
                    const SizedBox(height: 16),
                    _channelList(context),
                  ],
                )
              else
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 5, child: _composer()),
                    const SizedBox(width: 18),
                    Expanded(flex: 6, child: _channelList(context)),
                  ],
                ),
              const SizedBox(height: 16),
              const _SocialNotice(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _composer() {
    return _SocialPanel(
      title: 'Post composer',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'A product post can be adapted for each channel before publishing.',
            style: TextStyle(
              color: AppColors.text_secondary,
              fontSize: 12,
              height: 1.45,
            ),
          ),
          const SizedBox(height: 16),
          const _ComposerStep(
            number: '1',
            title: 'Choose a POS product',
            detail: 'Only active, published items will be available',
          ),
          const _ComposerStep(
            number: '2',
            title: 'Prepare media and caption',
            detail: 'Crop and tailor copy for each platform',
          ),
          const _ComposerStep(
            number: '3',
            title: 'Review and schedule',
            detail: 'Approve each post and track delivery status',
          ),
          const SizedBox(height: 10),
          const Text(
            'Composer will be enabled after catalog media storage and account connections are ready.',
            style: TextStyle(
              color: AppColors.text_tertiary,
              fontSize: 11,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _channelList(BuildContext context) {
    return _SocialPanel(
      title: 'Channels',
      child: Column(
        children: [
          for (final channel in _channels)
            _ChannelRow(
              channel: channel,
              onConnect: onConnect == null
                  ? null
                  : () => onConnect!(channel.name),
            ),
        ],
      ),
    );
  }
}

class _SocialChannel {
  const _SocialChannel({
    required this.name,
    required this.detail,
    required this.icon,
    required this.status,
  });

  final String name;
  final String detail;
  final IconData icon;
  final String status;
}

class _SocialPanel extends StatelessWidget {
  const _SocialPanel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.bg_surface,
        border: Border.all(color: AppColors.border_subtle),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.text_primary,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _ChannelRow extends StatelessWidget {
  const _ChannelRow({required this.channel, this.onConnect});

  final _SocialChannel channel;
  final VoidCallback? onConnect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 11),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border_subtle)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(channel.icon, color: AppColors.accent_primary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  channel.name,
                  style: const TextStyle(
                    color: AppColors.text_primary,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  channel.detail,
                  style: const TextStyle(
                    color: AppColors.text_tertiary,
                    fontSize: 11,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  channel.status,
                  style: const TextStyle(
                    color: AppColors.status_warning,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Tooltip(
            message: 'Official account connection is not configured yet.',
            child: OutlinedButton(
              onPressed: onConnect,
              child: const Text('Connect'),
            ),
          ),
        ],
      ),
    );
  }
}

class _ComposerStep extends StatelessWidget {
  const _ComposerStep({
    required this.number,
    required this.title,
    required this.detail,
  });

  final String number;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.accent_light,
              shape: BoxShape.circle,
            ),
            child: Text(
              number,
              style: const TextStyle(
                color: AppColors.accent_primary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.text_primary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  style: const TextStyle(
                    color: AppColors.text_tertiary,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SocialNotice extends StatelessWidget {
  const _SocialNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.bg_subtle,
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: AppColors.text_secondary, size: 18),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'No social accounts are connected. OAuth, token storage, platform review, publishing queues, and channel-specific permissions still need implementation.',
              style: TextStyle(
                color: AppColors.text_secondary,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
