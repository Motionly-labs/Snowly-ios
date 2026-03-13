//
//  CrewHeaderOverlay.swift
//  Snowly
//
//  Crew header overlay for the unified Map page.
//  Shows crew name, status, and expandable member list.
//

import SwiftUI

struct CrewHeaderOverlay: View {
    @Environment(CrewService.self) private var crewService
    @State private var showManageSheet = false
    @State private var isMemberListExpanded = false

    var body: some View {
        crewHeader
            .sheet(isPresented: $showManageSheet) {
                CrewManageSheet()
            }
    }

    // MARK: - Header with Expandable Member List

    private var crewHeader: some View {
        VStack(spacing: 0) {
            headerRow
            if isMemberListExpanded {
                Divider()
                    .padding(.horizontal, Spacing.md)
                memberList
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .snowlyGlass(in: RoundedRectangle(cornerRadius: CornerRadius.pill, style: .continuous))
        .animation(AnimationTokens.standardEaseInOut, value: isMemberListExpanded)
    }

    private var headerRow: some View {
        HStack(spacing: Spacing.sm) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)

            Text(crewService.activeCrew?.name ?? "")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Text(memberCountLabel)
                .font(.caption)
                .foregroundStyle(.secondary)

            if crewService.syncPreferences.mode == .manual {
                Text(String(localized: "crew_sync_badge_manual"))
                    .font(Typography.caption2Semibold)
                    .foregroundStyle(ColorTokens.warning)
                    .padding(.horizontal, Spacing.gap)
                    .padding(.vertical, Spacing.xxs)
                    .background(ColorTokens.warning.opacity(Opacity.gentle), in: Capsule())
            }

            Spacer(minLength: Spacing.xs)

            Button {
                isMemberListExpanded.toggle()
            } label: {
                Image(systemName: "chevron.down")
                    .font(Typography.captionSemibold)
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isMemberListExpanded ? -180 : 0))
                    .animation(AnimationTokens.standardEaseInOut, value: isMemberListExpanded)
            }

            if crewService.unreadPinCount > 0 {
                Button {
                    crewService.requestFocusOnLatestUnreadPin()
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "flag.fill")
                            .font(.subheadline)
                            .foregroundStyle(ColorTokens.warning)

                        Circle()
                            .fill(ColorTokens.error)
                            .frame(width: 9, height: 9)
                            .offset(x: 4, y: -4)
                    }
                }
                .accessibilityLabel(String(localized: "crew_pin_unread_accessibility_label"))
                .accessibilityHint(String(localized: "crew_pin_unread_accessibility_hint"))
            }

            Button {
                showManageSheet = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.sm)
        .contentShape(Rectangle())
        .onTapGesture {
            isMemberListExpanded.toggle()
        }
    }

    // MARK: - Member List (expanded)

    private var memberList: some View {
        let allMembers = crewService.activeCrew?.members ?? []
        return VStack(spacing: 0) {
            ForEach(allMembers) { member in
                memberRow(member)
                if member.id != allMembers.last?.id {
                    Divider()
                        .padding(.leading, 44)
                }
            }
        }
        .padding(.vertical, Spacing.gap)
    }

    private func memberRow(_ member: CrewMember) -> some View {
        HStack(spacing: Spacing.gutter) {
            Circle()
                .fill(member.isOnline ? Color.accentColor : .gray)
                .frame(width: 28, height: 28)
                .overlay {
                    Text(String(member.displayName.prefix(1)).uppercased())
                        .font(Typography.badgeLabel)
                        .foregroundStyle(.white)
                }

            Text(member.displayName)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)

            if member.isCreator {
                Text(String(localized: "crew_host"))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(.quaternary, in: Capsule())
            }

            Spacer()

            Circle()
                .fill(member.isOnline ? ColorTokens.sensorGreen : ColorTokens.sensorRed)
                .frame(width: 8, height: 8)
        }
        .padding(.horizontal, Spacing.lg)
        .padding(.vertical, Spacing.gap)
    }

    // MARK: - Helpers

    private var memberCountLabel: String {
        let members = crewService.activeCrew?.members ?? []
        let total = members.count
        let online = members.filter(\.isOnline).count
        return "(\(online)/\(total))"
    }

    private var statusColor: Color {
        if crewService.lastError != nil {
            return ColorTokens.sensorRed
        }
        if crewService.syncPreferences.mode == .manual {
            return ColorTokens.warning
        }
        return crewService.isActive ? ColorTokens.sensorGreen : ColorTokens.sensorRed
    }
}
