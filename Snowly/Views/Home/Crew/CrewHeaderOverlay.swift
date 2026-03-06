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
        .background(
            .ultraThinMaterial,
            in: RoundedRectangle(cornerRadius: CornerRadius.pill, style: .continuous)
        )
        .animation(.easeInOut(duration: 0.25), value: isMemberListExpanded)
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
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
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange.opacity(0.15), in: Capsule())
            }

            Spacer(minLength: 4)

            Button {
                isMemberListExpanded.toggle()
            } label: {
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isMemberListExpanded ? -180 : 0))
                    .animation(.easeInOut(duration: 0.25), value: isMemberListExpanded)
            }

            if crewService.unreadPinCount > 0 {
                Button {
                    crewService.requestFocusOnLatestUnreadPin()
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "flag.fill")
                            .font(.subheadline)
                            .foregroundStyle(.orange)

                        Circle()
                            .fill(.red)
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
        .padding(.vertical, 8)
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
        .padding(.vertical, 6)
    }

    private func memberRow(_ member: CrewMember) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(member.isOnline ? Color.accentColor : .gray)
                .frame(width: 28, height: 28)
                .overlay {
                    Text(String(member.displayName.prefix(1)).uppercased())
                        .font(.system(size: 12, weight: .bold))
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
        .padding(.vertical, 6)
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
            return .orange
        }
        return crewService.isActive ? ColorTokens.sensorGreen : ColorTokens.sensorRed
    }
}
