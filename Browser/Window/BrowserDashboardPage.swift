import AppKit
import SwiftUI

struct BrowserDashboardPage: View {
    @ObservedObject var browser: BrowserState
    @ObservedObject var session: BrowserSessionController
    let onClose: () -> Void

    @State private var selectedMessage: BrowserMailDashboardMessage?
    @State private var selectedSection: BrowserMailDashboardSection = .shipments

    private var dashboard: BrowserMailDashboard? { session.mailDashboard }
    private let dashboardTileHeight: CGFloat = 620
    private let sidebarWidth: CGFloat = 245
    private var dashboardColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 340), spacing: 20, alignment: .top)]
    }
    private var shipmentColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 270), spacing: 12, alignment: .top)]
    }

    var body: some View {
        ZStack {
            DashColor.bg.ignoresSafeArea()

            VStack(spacing: 0) {
                dashHeader
                if let dashboard {
                    dashboardShell(dashboard)
                } else {
                    emptyState
                }
            }
        }
        .foregroundStyle(DashColor.primary)
        .onAppear {
            session.refreshCloudData()
            DispatchQueue.main.async {
                session.ensureDashboardSectionLoaded(selectedSection)
            }
        }
        .onChange(of: selectedSection) { _, section in
            session.ensureDashboardSectionLoaded(section)
        }
        .onExitCommand(perform: onClose)
        .overlay {
            if let message = selectedMessage {
                DashEmailModal(
                    message: message,
                    onClose: { selectedMessage = nil },
                    onOpenMail: {
                        selectedMessage = nil
                        browser.newTab(url: BrowserInternalPage.mail.url)
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.97)))
            }
        }
        .animation(.easeInOut(duration: 0.18), value: selectedMessage?.id)
    }

    // MARK: Header

    private var dashHeader: some View {
        HStack(spacing: 10) {
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 28, height: 28)
                    .background(Color.white.opacity(0.06), in: Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            if session.hasConnectedGoogleAccount {
                Text(session.googleAccounts.first?.email ?? "")
                    .font(.system(size: 12, weight: .medium).monospaced())
                    .foregroundStyle(DashColor.tertiary)
            } else {
                Button { session.openGoogleConnectionURL() } label: {
                    Label("Connect Google", systemImage: "link")
                        .font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.bordered)
            }

            Button { session.analyzeRecentMail() } label: {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 13))
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.05), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Analyze recent mail")

            Button { session.refreshCloudData() } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 13))
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.05), in: Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.08), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Refresh")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    // MARK: Empty State

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "tray.and.arrow.down")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(DashColor.muted)
            Text("No Mail Analysis Yet")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DashColor.secondary)
            Text("Analyze recent imported mail to populate shipments, subscriptions, purchases, and security alerts.")
                .font(.system(size: 12))
                .foregroundStyle(DashColor.muted)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            Button { session.analyzeRecentMail() } label: {
                Label("Analyze Recent Mail", systemImage: "wand.and.stars")
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 9)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!session.hasConnectedGoogleAccount)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Command Center

    private func dashboardShell(_ dashboard: BrowserMailDashboard) -> some View {
        HStack(spacing: 0) {
            dashboardSidebar(dashboard)
                .frame(width: sidebarWidth)
                .padding(.horizontal, 14)
                .padding(.bottom, 18)

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 1)

            activeDashboardSection(dashboard)
                .padding(22)
        }
    }

    private func dashboardSidebar(_ dashboard: BrowserMailDashboard) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Text("Mail")
                    .font(.system(size: 11, weight: .semibold).monospaced())
                    .foregroundStyle(DashColor.muted)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 4)

                ForEach(BrowserMailDashboardSection.allCases, id: \.self) { section in
                    DashSidebarButton(
                        title: sidebarTitle(for: section),
                        systemImage: sidebarImage(for: section),
                        isSelected: selectedSection == section,
                        isLoading: session.isLoadingDashboardSection(section)
                    ) {
                        selectedSection = section
                    }
                }
            }
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func activeDashboardSection(_ d: BrowserMailDashboard) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Label(sidebarTitle(for: selectedSection), systemImage: sidebarImage(for: selectedSection))
                    .font(.system(size: 22, weight: .semibold))
                Spacer()
            }

            sectionContent(d)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func sectionContent(_ d: BrowserMailDashboard) -> some View {
        switch selectedSection {
        case .shipments:
            populatedOrLoading(d.shipments, section: .shipments) {
                shipmentsSection(d.shipments, section: .shipments)
            }
        case .subscriptions:
            populatedOrLoading(d.subscriptions, section: .subscriptions) {
                subscriptionsCard(d.subscriptions, section: .subscriptions)
            }
        case .orders:
            populatedOrLoading(d.orders, section: .orders) {
                purchasesCard(d.orders, section: .orders)
            }
        case .securityCodes:
            populatedOrLoading(d.securityCodes, section: .securityCodes) {
                securityCodesCard(d.securityCodes, section: .securityCodes)
            }
        case .notifications:
            populatedOrLoading(d.notifications, section: .notifications) {
                notificationsCard(d.notifications, section: .notifications)
            }
        case .supportThreads:
            populatedOrLoading(d.supportThreads, section: .supportThreads) {
                supportCard(d.supportThreads, section: .supportThreads)
            }
        case .invoices:
            populatedOrLoading(d.invoices, section: .invoices) {
                invoicesCard(d.invoices, section: .invoices)
            }
        case .bookings:
            populatedOrLoading(d.bookings, section: .bookings) {
                bookingsCard(d.bookings, section: .bookings)
            }
        case .meetingsEvents:
            populatedOrLoading(d.meetingsEvents, section: .meetingsEvents) {
                meetingsEventsCard(d.meetingsEvents, section: .meetingsEvents)
            }
        case .securityNotifications:
            populatedOrLoading(d.securityNotifications, section: .securityNotifications) {
                securityCard(d.securityNotifications, section: .securityNotifications)
            }
        case .promotions:
            populatedOrLoading(d.promotions, section: .promotions) {
                classificationCard(title: "Promotions", systemImage: "megaphone", rows: d.promotions, section: .promotions)
            }
        case .spam:
            populatedOrLoading(d.spam, section: .spam) {
                classificationCard(title: "Spam", systemImage: "exclamationmark.octagon", rows: d.spam, section: .spam)
            }
        }
    }

    @ViewBuilder
    private func populatedOrLoading<Rows: Collection, Content: View>(
        _ rows: Rows,
        section: BrowserMailDashboardSection,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if !rows.isEmpty {
            content()
        } else if session.isLoadingDashboardSection(section) {
            DashCard {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading \(sidebarTitle(for: section).lowercased())")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(DashColor.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: dashboardTileHeight)
        } else {
            DashCard {
                VStack(spacing: 10) {
                    Image(systemName: sidebarImage(for: section))
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(DashColor.muted)
                    Text("No \(sidebarTitle(for: section).lowercased())")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DashColor.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(height: dashboardTileHeight)
            .onAppear {
                session.ensureDashboardSectionLoaded(section)
            }
        }
    }

    private func sidebarTitle(for section: BrowserMailDashboardSection) -> String {
        switch section {
        case .shipments: return "Shipping"
        case .subscriptions: return "Subscriptions"
        case .orders: return "Purchases"
        case .securityCodes: return "Security Codes"
        case .notifications: return "Notifications"
        case .supportThreads: return "Support"
        case .invoices: return "Invoices"
        case .bookings: return "Bookings"
        case .meetingsEvents: return "Meetings & Events"
        case .securityNotifications: return "Security"
        case .promotions: return "Promotions"
        case .spam: return "Spam"
        }
    }

    private func sidebarImage(for section: BrowserMailDashboardSection) -> String {
        switch section {
        case .shipments: return "shippingbox"
        case .subscriptions: return "arrow.triangle.2.circlepath"
        case .orders: return "bag"
        case .securityCodes: return "key.horizontal"
        case .notifications: return "bell.badge"
        case .supportThreads: return "lifepreserver"
        case .invoices: return "doc.text"
        case .bookings: return "ticket"
        case .meetingsEvents: return "calendar.badge.clock"
        case .securityNotifications: return "lock.shield"
        case .promotions: return "megaphone"
        case .spam: return "exclamationmark.octagon"
        }
    }

    @ViewBuilder
    private func commandCenter(_ d: BrowserMailDashboard) -> some View {
        let hasAlerts = !d.securityNotifications.isEmpty

        LazyVGrid(columns: dashboardColumns, alignment: .leading, spacing: 20) {
            if !d.shipments.isEmpty {
                shipmentsSection(d.shipments, section: .shipments)
            }

            if !d.subscriptions.isEmpty {
                subscriptionsCard(d.subscriptions, section: .subscriptions)
            }

            if !d.orders.isEmpty {
                purchasesCard(d.orders, section: .orders)
            }

            if !d.securityCodes.isEmpty {
                securityCodesCard(d.securityCodes, section: .securityCodes)
            }

            if !d.notifications.isEmpty {
                notificationsCard(d.notifications, section: .notifications)
            }

            if !d.supportThreads.isEmpty {
                supportCard(d.supportThreads, section: .supportThreads)
            }

            if !d.invoices.isEmpty {
                invoicesCard(d.invoices, section: .invoices)
            }

            if !d.bookings.isEmpty {
                bookingsCard(d.bookings, section: .bookings)
            }

            if !d.meetingsEvents.isEmpty {
                meetingsEventsCard(d.meetingsEvents, section: .meetingsEvents)
            }

            if hasAlerts {
                securityCard(d.securityNotifications, section: .securityNotifications)
            }

            if !d.promotions.isEmpty {
                classificationCard(title: "Promotions", systemImage: "megaphone", rows: d.promotions, section: .promotions)
            }

            if !d.spam.isEmpty {
                classificationCard(title: "Spam", systemImage: "exclamationmark.octagon", rows: d.spam, section: .spam)
            }
        }
    }

    // MARK: Sections

    private func shipmentsSection(_ shipments: [BrowserMailShipmentSummary], section: BrowserMailDashboardSection) -> some View {
        let sortedShipments = shipmentsSortedByDate(shipments)
        let activeShipments = sortedShipments.filter { !isDeliveredShipment($0) }
        let deliveredShipments = sortedShipments.filter(isDeliveredShipment)

        return DashCard {
            DashSectionHeader(title: "Shipping", count: "\(shipments.count)", systemImage: "shippingbox")

            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 16) {
                    if !activeShipments.isEmpty {
                        shipmentGroup(
                            title: "Ordered / on the way",
                            shipments: activeShipments,
                            highlightsArriving: true
                        )
                    }

                    if !deliveredShipments.isEmpty {
                        shipmentGroup(
                            title: "Delivered",
                            shipments: deliveredShipments,
                            highlightsArriving: false
                        )
                    }

                    dashboardPagingFooter(for: section)
                }
                .padding(.trailing, 2)
            }
            .padding(.top, 13)
        }
        .frame(height: dashboardTileHeight)
    }

    private func subscriptionsCard(_ subs: [BrowserMailSubscriptionSummary], section: BrowserMailDashboardSection) -> some View {
        let sortedSubscriptions = subscriptionsSortedByDate(subs)
        let activeSubscriptions = sortedSubscriptions.filter { !isPastSubscription($0) }
        let pastSubscriptions = sortedSubscriptions.filter(isPastSubscription)

        return DashCard {
            DashSectionHeader(title: "Subscriptions", count: "\(subs.count)", systemImage: "arrow.triangle.2.circlepath")
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 16) {
                    if !activeSubscriptions.isEmpty {
                        subscriptionGroup(title: "Active", subscriptions: activeSubscriptions)
                    }

                    if !pastSubscriptions.isEmpty {
                        subscriptionGroup(title: "Past", subscriptions: pastSubscriptions)
                    }

                    dashboardPagingFooter(for: section)
                }
                .padding(.trailing, 2)
            }
            .padding(.top, 14)
        }
        .frame(height: dashboardTileHeight)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func shipmentGroup(
        title: String,
        shipments: [BrowserMailShipmentSummary],
        highlightsArriving: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                DashSubsectionHeader(title: title, count: shipments.count)

                if highlightsArriving {
                    let arriving = shipments.filter(isArrivingShipment).count
                    if arriving > 0 {
                        HStack(spacing: 5) {
                            Circle().fill(DashColor.amber).frame(width: 6, height: 6)
                            Text("\(arriving) arriving today")
                                .font(.system(size: 11.5, weight: .medium))
                                .foregroundStyle(DashColor.amber)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(DashColor.amber.opacity(0.12), in: Capsule())
                    }
                }
            }

            LazyVGrid(columns: shipmentColumns, spacing: 12) {
                ForEach(shipments) { shipment in
                    DashShipmentCard(shipment: shipment) {
                        selectedMessage = shipment.message ?? shipment.messages?.first
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func subscriptionGroup(title: String, subscriptions: [BrowserMailSubscriptionSummary]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            DashSubsectionHeader(title: title, count: subscriptions.count)

            VStack(spacing: 10) {
                ForEach(subscriptions) { sub in
                    DashSubscriptionRow(sub: sub) {
                        selectedMessage = sub.message ?? sub.messages.first
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func securityCodesCard(_ codes: [BrowserMailSecurityCode], section: BrowserMailDashboardSection) -> some View {
        DashCard {
            DashSectionHeader(title: "Security codes", count: "\(codes.count)", systemImage: "key.horizontal")
            ScrollView(.vertical) {
                VStack(spacing: 10) {
                    ForEach(sortedSecurityCodes(codes)) { code in
                        DashInfoRow(
                            systemImage: "number",
                            title: code.serviceName ?? "Security code",
                            detail: code.message?.subject ?? "One-time code",
                            tag: code.code,
                            date: code.message?.displayDate ?? date(fromMilliseconds: code.updatedAt),
                            tagStyle: .accent
                        ) {
                            selectedMessage = code.message
                        }
                    }
                    dashboardPagingFooter(for: section)
                }
                .padding(.trailing, 2)
            }
            .padding(.top, 14)
        }
        .frame(height: dashboardTileHeight)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func notificationsCard(_ notifications: [BrowserMailNotification], section: BrowserMailDashboardSection) -> some View {
        DashCard {
            DashSectionHeader(title: "Notifications", count: "\(notifications.count)", systemImage: "bell.badge")
            ScrollView(.vertical) {
                VStack(spacing: 10) {
                    ForEach(sortedNotifications(notifications)) { notification in
                        DashInfoRow(
                            systemImage: "bell",
                            title: notification.title ?? notification.serviceName ?? dashboardTitle(notification.notificationType),
                            detail: [notification.serviceName, notification.url].compactMap { $0 }.joined(separator: " · "),
                            tag: notification.status == "unknown" ? dashboardTitle(notification.notificationType) : notification.status,
                            date: notification.message?.displayDate ?? date(fromMilliseconds: notification.occurredAt ?? notification.updatedAt)
                        ) {
                            selectedMessage = notification.message
                        }
                    }
                    dashboardPagingFooter(for: section)
                }
                .padding(.trailing, 2)
            }
            .padding(.top, 14)
        }
        .frame(height: dashboardTileHeight)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func supportCard(_ threads: [BrowserMailSupportThreadSummary], section: BrowserMailDashboardSection) -> some View {
        DashCard {
            DashSectionHeader(title: "Support", count: "\(threads.count)", systemImage: "lifepreserver")
            ScrollView(.vertical) {
                VStack(spacing: 10) {
                    ForEach(sortedSupportThreads(threads)) { thread in
                        DashInfoRow(
                            systemImage: "lifepreserver",
                            title: thread.companyName,
                            detail: [thread.ticketId, thread.subject].compactMap { $0 }.joined(separator: " · "),
                            tag: thread.status,
                            date: thread.message?.displayDate ?? date(fromMilliseconds: thread.updatedAt)
                        ) {
                            selectedMessage = thread.message ?? thread.messages?.first
                        }
                    }
                    dashboardPagingFooter(for: section)
                }
                .padding(.trailing, 2)
            }
            .padding(.top, 14)
        }
        .frame(height: dashboardTileHeight)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func invoicesCard(_ invoices: [BrowserMailInvoiceSummary], section: BrowserMailDashboardSection) -> some View {
        let groups = invoiceGroups(from: invoices)

        return ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(groups) { group in
                    invoicePanel(group)
                }

                dashboardPagingFooter(for: section)
            }
            .padding(.trailing, 2)
        }
        .frame(height: dashboardTileHeight)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func invoicePanel(_ group: InvoicePanelGroup) -> some View {
        DashCard(fillsHeight: false) {
            DashPanelHeader(title: group.title, count: group.invoices.count, systemImage: group.systemImage, tint: group.tint)

            VStack(spacing: 10) {
                ForEach(group.invoices) { invoice in
                    DashInfoRow(
                        systemImage: "doc.text",
                        title: invoice.vendor ?? "Invoice",
                        detail: [invoice.invoiceNumber, moneyText(amount: invoice.amount, currency: invoice.currency)]
                            .compactMap { $0 }
                            .joined(separator: " · "),
                        tag: invoice.status,
                        date: invoice.message?.displayDate ?? date(fromMilliseconds: invoice.updatedAt)
                    ) {
                        selectedMessage = invoice.message ?? invoice.messages?.first
                    }
                }
            }
            .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func bookingsCard(_ bookings: [BrowserMailBookingSummary], section: BrowserMailDashboardSection) -> some View {
        let groups = bookingGroups(from: bookings)

        return ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(groups) { group in
                    bookingPanel(group)
                }

                dashboardPagingFooter(for: section)
            }
            .padding(.trailing, 2)
        }
        .frame(height: dashboardTileHeight)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func bookingPanel(_ group: BookingPanelGroup) -> some View {
        DashCard(fillsHeight: false) {
            DashPanelHeader(title: group.title, count: group.bookings.count, systemImage: group.systemImage, tint: group.tint)

            VStack(spacing: 10) {
                ForEach(group.bookings) { booking in
                    DashInfoRow(
                        systemImage: group.systemImage,
                        title: booking.title ?? booking.provider ?? dashboardTitle(booking.category),
                        detail: [
                            booking.confirmationNumber,
                            booking.bookingCode,
                            booking.location,
                            moneyText(amount: booking.amount, currency: booking.currency)
                        ]
                            .compactMap { $0 }
                            .joined(separator: " · "),
                        tag: booking.status ?? booking.category,
                        date: date(fromMilliseconds: booking.startTime) ?? booking.message?.displayDate ?? date(fromMilliseconds: booking.updatedAt)
                    ) {
                        selectedMessage = booking.message ?? booking.messages?.first
                    }
                }
            }
            .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func meetingsEventsCard(_ events: [BrowserMailMeetingEventSummary], section: BrowserMailDashboardSection) -> some View {
        DashCard {
            DashSectionHeader(title: "Meetings & events", count: "\(events.count)", systemImage: "calendar.badge.clock")
            ScrollView(.vertical) {
                VStack(spacing: 10) {
                    ForEach(sortedMeetingEvents(events)) { event in
                        DashInfoRow(
                            systemImage: "calendar",
                            title: event.title ?? event.provider ?? "Event",
                            detail: [event.provider, event.location, event.url].compactMap { $0 }.joined(separator: " · "),
                            tag: event.status,
                            date: date(fromMilliseconds: event.startTime) ?? event.message?.displayDate ?? date(fromMilliseconds: event.updatedAt)
                    ) {
                        selectedMessage = event.message ?? event.messages?.first
                    }
                }
                    dashboardPagingFooter(for: section)
                }
                .padding(.trailing, 2)
            }
            .padding(.top, 14)
        }
        .frame(height: dashboardTileHeight)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func classificationCard(
        title: String,
        systemImage: String,
        rows: [BrowserMailClassificationSummary],
        section: BrowserMailDashboardSection
    ) -> some View {
        DashCard {
            DashSectionHeader(title: title, count: "\(rows.count)", systemImage: systemImage)
            ScrollView(.vertical) {
                VStack(spacing: 10) {
                    ForEach(sortedClassifications(rows)) { row in
                        DashInfoRow(
                            systemImage: systemImage,
                            title: row.message?.subject ?? dashboardTitle(row.category),
                            detail: [row.message?.from, row.reason].compactMap { $0 }.joined(separator: " · "),
                            tag: dashboardTitle(row.category),
                            date: row.message?.displayDate ?? date(fromMilliseconds: row.updatedAt)
                        ) {
                            selectedMessage = row.message
                        }
                    }
                    dashboardPagingFooter(for: section)
                }
                .padding(.trailing, 2)
            }
            .padding(.top, 14)
        }
        .frame(height: dashboardTileHeight)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func purchasesCard(_ orders: [BrowserMailOrderSummary], section: BrowserMailDashboardSection) -> some View {
        let groups = purchaseGroups(from: orders)

        return ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(groups) { group in
                    purchasePanel(group)
                }

                dashboardPagingFooter(for: section)
            }
            .padding(.trailing, 2)
        }
        .frame(height: dashboardTileHeight)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func purchasePanel(_ group: PurchasePanelGroup) -> some View {
        DashCard(fillsHeight: false) {
            DashPanelHeader(title: group.title, count: group.orders.count, systemImage: group.systemImage, tint: group.tint)

            VStack(spacing: 9) {
                ForEach(group.orders) { order in
                    DashPurchaseRow(order: order) {
                        selectedMessage = order.messages.first ?? order.message
                    }
                }
            }
            .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func securityCard(_ alerts: [BrowserMailSecurityNotification], section: BrowserMailDashboardSection) -> some View {
        let groups = securityAlertGroups(from: alerts)

        return ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(groups) { group in
                    securityEventPanel(group)
                }

                dashboardPagingFooter(for: section)
            }
            .padding(.trailing, 2)
        }
        .frame(height: dashboardTileHeight)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func securityEventPanel(_ group: SecurityAlertGroup) -> some View {
        DashCard(fillsHeight: false) {
            HStack(spacing: 9) {
                Image(systemName: group.systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(group.tint)
                    .frame(width: 18)

                Text(group.title)
                    .font(.system(size: 16, weight: .semibold))

                Spacer()

                Text("\(group.alerts.count)")
                    .font(.system(size: 12, weight: .semibold).monospaced())
                    .foregroundStyle(DashColor.muted)
            }

            VStack(spacing: 10) {
                ForEach(group.alerts) { alert in
                    DashSecurityRow(alert: alert) {
                        selectedMessage = alert.message
                    }
                }
            }
            .padding(.top, 14)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func dashboardPagingFooter(for section: BrowserMailDashboardSection) -> some View {
        DashPagingFooter(
            hasMore: session.hasMoreDashboardSection(section),
            isLoading: session.isLoadingDashboardSection(section),
            onLoadMore: { session.loadMoreDashboardSection(section) }
        )
    }

    private func tuckedCard(promoCount: Int, spamCount: Int) -> some View {
        DashCard(dashed: true) {
            HStack {
                Text("Tucked away")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DashColor.dim)
                Spacer()
                Text("low priority")
                    .font(.system(size: 11.5, weight: .semibold).monospaced())
                    .foregroundStyle(DashColor.muted)
            }
            HStack(spacing: 10) {
                DashTuckedStat(count: promoCount, label: "Promotions")
                DashTuckedStat(count: spamCount, label: "Spam")
            }
            .padding(.top, 12)
        }
        .frame(height: dashboardTileHeight)
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func shipmentsSortedByDate(_ shipments: [BrowserMailShipmentSummary]) -> [BrowserMailShipmentSummary] {
        shipments.sorted { shipmentSortTimestamp($0) > shipmentSortTimestamp($1) }
    }

    private func subscriptionsSortedByDate(_ subscriptions: [BrowserMailSubscriptionSummary]) -> [BrowserMailSubscriptionSummary] {
        subscriptions.sorted { subscriptionSortTimestamp($0) > subscriptionSortTimestamp($1) }
    }

    private func sortedOrders(_ orders: [BrowserMailOrderSummary]) -> [BrowserMailOrderSummary] {
        orders.sorted { orderSortTimestamp($0) > orderSortTimestamp($1) }
    }

    private func purchaseGroups(from orders: [BrowserMailOrderSummary]) -> [PurchasePanelGroup] {
        let grouped = Dictionary(grouping: sortedOrders(orders), by: purchaseGroupKey)
        return grouped.map { key, orders in
            let info = purchaseGroupInfo(for: key)
            return PurchasePanelGroup(
                id: key,
                title: info.title,
                systemImage: info.systemImage,
                tint: info.tint,
                orders: orders
            )
        }
        .sorted { purchaseGroupTimestamp($0) > purchaseGroupTimestamp($1) }
    }

    private func purchaseGroupTimestamp(_ group: PurchasePanelGroup) -> Double {
        group.orders.map(orderSortTimestamp).max() ?? 0
    }

    private func purchaseGroupKey(_ order: BrowserMailOrderSummary) -> String {
        let status = normalizedStatusKey(order.status)
        let signal = purchaseSignalText(order)

        if status.contains("cancel") || status.contains("refund") {
            return "cancelled"
        }
        if status.contains("pickup") ||
            status.contains("collect") ||
            signal.contains("pickup") ||
            signal.contains("pick up") ||
            signal.contains("takeaway") ||
            signal.contains("takeout") ||
            signal.contains("food order") ||
            signal.contains("restaurant") ||
            signal.contains("ubereats") ||
            signal.contains("uber eats") ||
            signal.contains("doordash") ||
            signal.contains("door dash") ||
            signal.contains("deliveroo") ||
            signal.contains("menulog") {
            return "pickup_food"
        }
        if status.contains("delivered") || status.contains("complete") || status.contains("fulfilled") || status.contains("picked_up") {
            return "completed"
        }
        return "recent"
    }

    private func purchaseGroupInfo(for key: String) -> (title: String, systemImage: String, tint: Color) {
        switch key {
        case "pickup_food":
            return ("Pickup & food orders", "takeoutbag.and.cup.and.straw", DashColor.amber)
        case "completed":
            return ("Completed purchases", "checkmark.circle", Color(red: 0.29, green: 0.86, blue: 0.5))
        case "cancelled":
            return ("Cancelled & refunded", "xmark.circle", Color(rgbHex: 0xf87171))
        default:
            return ("Recent purchases", "bag", DashColor.tertiary)
        }
    }

    private func purchaseSignalText(_ order: BrowserMailOrderSummary) -> String {
        [
            order.merchant,
            order.itemSummary,
            order.orderNumber,
            order.status,
            order.message?.subject,
            order.message?.snippet,
            order.messages.first?.subject,
            order.messages.first?.snippet,
        ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
    }

    private func sortedSecurityCodes(_ codes: [BrowserMailSecurityCode]) -> [BrowserMailSecurityCode] {
        codes.sorted { dashboardSortTimestamp(message: $0.message, fallback: $0.updatedAt) > dashboardSortTimestamp(message: $1.message, fallback: $1.updatedAt) }
    }

    private func sortedSecurityNotifications(_ alerts: [BrowserMailSecurityNotification]) -> [BrowserMailSecurityNotification] {
        alerts.sorted {
            dashboardSortTimestamp(message: $0.message, fallback: $0.occurredAt ?? $0.updatedAt) >
                dashboardSortTimestamp(message: $1.message, fallback: $1.occurredAt ?? $1.updatedAt)
        }
    }

    private func securityAlertGroups(from alerts: [BrowserMailSecurityNotification]) -> [SecurityAlertGroup] {
        let grouped = Dictionary(grouping: sortedSecurityNotifications(alerts), by: securityAlertGroupKey)
        return grouped.map { key, alerts in
            let info = securityAlertGroupInfo(for: key)
            return SecurityAlertGroup(
                id: key,
                title: info.title,
                systemImage: info.systemImage,
                tint: info.tint,
                alerts: alerts
            )
        }
        .sorted {
            securityGroupTimestamp($0) > securityGroupTimestamp($1)
        }
    }

    private func securityGroupTimestamp(_ group: SecurityAlertGroup) -> Double {
        group.alerts
            .map { dashboardSortTimestamp(message: $0.message, fallback: $0.occurredAt ?? $0.updatedAt) }
            .max() ?? 0
    }

    private func securityAlertGroupKey(_ alert: BrowserMailSecurityNotification) -> String {
        let type = normalizedStatusKey(alert.notificationType)
        let subject = alert.message?.subject?.lowercased() ?? ""
        let signal = "\(type) \(subject)"

        if signal.contains("sign_in") ||
            signal.contains("signin") ||
            signal.contains("login") ||
            signal.contains("device") {
            return "sign_ins"
        }

        if signal.contains("password") ||
            signal.contains("recovery") ||
            signal.contains("reset") {
            return "passwords"
        }

        if signal.contains("verify") ||
            signal.contains("verification") ||
            signal.contains("signup") ||
            signal.contains("email") {
            return "verification"
        }

        if signal.contains("suspicious") ||
            signal.contains("warning") ||
            signal.contains("blocked") ||
            signal.contains("risk") {
            return "warnings"
        }

        return "account_security"
    }

    private func securityAlertGroupInfo(for key: String) -> (title: String, systemImage: String, tint: Color) {
        switch key {
        case "sign_ins":
            return ("Sign-ins & devices", "person.crop.circle.badge.checkmark", Color(rgbHex: 0x60a5fa))
        case "passwords":
            return ("Passwords & recovery", "key.horizontal", DashColor.amber)
        case "verification":
            return ("Verification", "checkmark.shield", Color(red: 0.29, green: 0.86, blue: 0.5))
        case "warnings":
            return ("Warnings", "exclamationmark.triangle", Color(rgbHex: 0xf87171))
        default:
            return ("Account security", "lock.shield", DashColor.tertiary)
        }
    }

    private func sortedNotifications(_ notifications: [BrowserMailNotification]) -> [BrowserMailNotification] {
        notifications.sorted {
            dashboardSortTimestamp(message: $0.message, fallback: $0.occurredAt ?? $0.updatedAt) >
                dashboardSortTimestamp(message: $1.message, fallback: $1.occurredAt ?? $1.updatedAt)
        }
    }

    private func sortedSupportThreads(_ threads: [BrowserMailSupportThreadSummary]) -> [BrowserMailSupportThreadSummary] {
        threads.sorted {
            dashboardSortTimestamp(message: $0.message ?? $0.messages?.first, fallback: $0.updatedAt) >
                dashboardSortTimestamp(message: $1.message ?? $1.messages?.first, fallback: $1.updatedAt)
        }
    }

    private func sortedInvoices(_ invoices: [BrowserMailInvoiceSummary]) -> [BrowserMailInvoiceSummary] {
        invoices.sorted {
            dashboardSortTimestamp(message: $0.message ?? $0.messages?.first, fallback: $0.updatedAt) >
                dashboardSortTimestamp(message: $1.message ?? $1.messages?.first, fallback: $1.updatedAt)
        }
    }

    private func invoiceGroups(from invoices: [BrowserMailInvoiceSummary]) -> [InvoicePanelGroup] {
        let grouped = Dictionary(grouping: sortedInvoices(invoices), by: invoiceGroupKey)
        return grouped.map { key, invoices in
            let info = invoiceGroupInfo(for: key)
            return InvoicePanelGroup(
                id: key,
                title: info.title,
                systemImage: info.systemImage,
                tint: info.tint,
                invoices: invoices
            )
        }
        .sorted { invoiceGroupTimestamp($0) > invoiceGroupTimestamp($1) }
    }

    private func invoiceGroupTimestamp(_ group: InvoicePanelGroup) -> Double {
        group.invoices
            .map { dashboardSortTimestamp(message: $0.message ?? $0.messages?.first, fallback: $0.updatedAt) }
            .max() ?? 0
    }

    private func invoiceGroupKey(_ invoice: BrowserMailInvoiceSummary) -> String {
        let status = normalizedStatusKey(invoice.status)
        if status.contains("overdue") ||
            status.contains("past_due") ||
            status.contains("failed") ||
            status.contains("declined") ||
            status.contains("unpaid") ||
            status.contains("due") {
            return "needs_attention"
        }
        if status.contains("paid") || status.contains("confirmed") || status.contains("received") {
            return "paid"
        }
        return "other"
    }

    private func invoiceGroupInfo(for key: String) -> (title: String, systemImage: String, tint: Color) {
        switch key {
        case "needs_attention":
            return ("Needs attention", "exclamationmark.circle", Color(rgbHex: 0xf87171))
        case "paid":
            return ("Paid & confirmed", "checkmark.circle", Color(red: 0.29, green: 0.86, blue: 0.5))
        default:
            return ("Invoices & payments", "doc.text", DashColor.tertiary)
        }
    }

    private func sortedBookings(_ bookings: [BrowserMailBookingSummary]) -> [BrowserMailBookingSummary] {
        bookings.sorted {
            ($0.startTime ?? dashboardSortTimestamp(message: $0.message ?? $0.messages?.first, fallback: $0.updatedAt)) >
                ($1.startTime ?? dashboardSortTimestamp(message: $1.message ?? $1.messages?.first, fallback: $1.updatedAt))
        }
    }

    private func bookingGroups(from bookings: [BrowserMailBookingSummary]) -> [BookingPanelGroup] {
        let grouped = Dictionary(grouping: sortedBookings(bookings), by: bookingGroupKey)
        return grouped.map { key, bookings in
            let info = bookingGroupInfo(for: key)
            return BookingPanelGroup(
                id: key,
                title: info.title,
                systemImage: info.systemImage,
                tint: info.tint,
                bookings: bookings
            )
        }
        .sorted { bookingGroupTimestamp($0) > bookingGroupTimestamp($1) }
    }

    private func bookingGroupTimestamp(_ group: BookingPanelGroup) -> Double {
        group.bookings
            .map { $0.startTime ?? dashboardSortTimestamp(message: $0.message ?? $0.messages?.first, fallback: $0.updatedAt) }
            .max() ?? 0
    }

    private func bookingGroupKey(_ booking: BrowserMailBookingSummary) -> String {
        let signal = bookingSignalText(booking)
        let category = normalizedStatusKey(booking.category)

        if signal.contains("pickup") ||
            signal.contains("takeaway") ||
            signal.contains("takeout") ||
            signal.contains("ubereats") ||
            signal.contains("uber eats") ||
            signal.contains("doordash") ||
            signal.contains("door dash") ||
            signal.contains("deliveroo") ||
            signal.contains("menulog") {
            return "food_orders"
        }
        if category.contains("flight") ||
            category.contains("hotel") ||
            category.contains("rental") ||
            signal.contains("flight") ||
            signal.contains("hotel") ||
            signal.contains("itinerary") ||
            signal.contains("boarding") ||
            signal.contains("rental") {
            return "travel"
        }
        if category.contains("event") ||
            signal.contains("ticket") ||
            signal.contains("concert") ||
            signal.contains("show") ||
            signal.contains("festival") ||
            signal.contains("venue") {
            return "tickets_events"
        }
        if signal.contains("restaurant") ||
            signal.contains("dining") ||
            signal.contains("table") ||
            signal.contains("reservation") ||
            signal.contains("appointment") {
            return "reservations"
        }
        return "other"
    }

    private func bookingGroupInfo(for key: String) -> (title: String, systemImage: String, tint: Color) {
        switch key {
        case "food_orders":
            return ("Food orders", "takeoutbag.and.cup.and.straw", DashColor.amber)
        case "travel":
            return ("Travel & stays", "airplane.departure", Color(rgbHex: 0x60a5fa))
        case "tickets_events":
            return ("Tickets & events", "ticket", Color(rgbHex: 0xc084fc))
        case "reservations":
            return ("Reservations & appointments", "calendar.badge.clock", Color(red: 0.29, green: 0.86, blue: 0.5))
        default:
            return ("Other bookings", "bookmark", DashColor.tertiary)
        }
    }

    private func bookingSignalText(_ booking: BrowserMailBookingSummary) -> String {
        [
            booking.category,
            booking.provider,
            booking.title,
            booking.location,
            booking.status,
            booking.message?.subject,
            booking.message?.snippet,
            booking.messages?.first?.subject,
            booking.messages?.first?.snippet,
        ]
            .compactMap { $0 }
            .joined(separator: " ")
            .lowercased()
    }

    private func sortedMeetingEvents(_ events: [BrowserMailMeetingEventSummary]) -> [BrowserMailMeetingEventSummary] {
        events.sorted {
            ($0.startTime ?? dashboardSortTimestamp(message: $0.message ?? $0.messages?.first, fallback: $0.updatedAt)) >
                ($1.startTime ?? dashboardSortTimestamp(message: $1.message ?? $1.messages?.first, fallback: $1.updatedAt))
        }
    }

    private func sortedClassifications(_ rows: [BrowserMailClassificationSummary]) -> [BrowserMailClassificationSummary] {
        rows.sorted {
            dashboardSortTimestamp(message: $0.message, fallback: $0.updatedAt) >
                dashboardSortTimestamp(message: $1.message, fallback: $1.updatedAt)
        }
    }

    private func shipmentSortTimestamp(_ shipment: BrowserMailShipmentSummary) -> Double {
        dashboardSortTimestamp(message: shipment.message ?? shipment.messages?.first, fallback: shipment.updatedAt)
    }

    private func subscriptionSortTimestamp(_ subscription: BrowserMailSubscriptionSummary) -> Double {
        dashboardSortTimestamp(message: subscription.message ?? subscription.messages.first, fallback: subscription.updatedAt)
    }

    private func orderSortTimestamp(_ order: BrowserMailOrderSummary) -> Double {
        dashboardSortTimestamp(message: order.message ?? order.messages.first, fallback: order.updatedAt)
    }

    private func dashboardSortTimestamp(message: BrowserMailDashboardMessage?, fallback: Double) -> Double {
        message?.internalDate ?? fallback
    }

    private func isArrivingShipment(_ shipment: BrowserMailShipmentSummary) -> Bool {
        let status = normalizedStatusKey(shipment.status)
        return status == "out_for_delivery" || status == "out for delivery"
    }

    private func isDeliveredShipment(_ shipment: BrowserMailShipmentSummary) -> Bool {
        normalizedStatusKey(shipment.status).contains("delivered")
    }

    private func isPastSubscription(_ subscription: BrowserMailSubscriptionSummary) -> Bool {
        let status = normalizedStatusKey(subscription.status)
        return status.contains("cancel") ||
            status.contains("expired") ||
            status.contains("ended") ||
            status.contains("inactive") ||
            status.contains("terminated")
    }

    private func normalizedStatusKey(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    private func date(fromMilliseconds milliseconds: Double?) -> Date? {
        milliseconds.map { Date(timeIntervalSince1970: $0 / 1000) }
    }

    private func moneyText(amount: Double?, currency: String?) -> String? {
        guard let amount else { return nil }
        return "\(currency ?? "") \(amount.formatted(.number.precision(.fractionLength(2))))"
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nonEmpty
    }

    private func dashboardTitle(_ raw: String) -> String {
        raw.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
}

// MARK: - Color Palette

private enum DashColor {
    static let bg      = Color(rgbHex: 0x0a0a0a)
    static let card    = Color(rgbHex: 0x161616)
    static let row     = Color(rgbHex: 0x1e1e1e)
    static let rowHov  = Color(rgbHex: 0x222831)
    static let sunken  = Color(rgbHex: 0x121212)
    static let primary = Color(rgbHex: 0xf2f2f2)
    static let secondary = Color(rgbHex: 0xe5e5e5)
    static let tertiary  = Color(rgbHex: 0xa3a3a3)
    static let dim       = Color(rgbHex: 0xb3b3b3)
    static let muted     = Color(rgbHex: 0x686868)
    static let faint     = Color(rgbHex: 0x7a7a7a)
    static let amber     = Color(rgbHex: 0xf7c869)
}

private extension Color {
    init(rgbHex hex: UInt32) {
        self.init(
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue:  Double( hex        & 0xFF) / 255
        )
    }
}

private struct SecurityAlertGroup: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let tint: Color
    let alerts: [BrowserMailSecurityNotification]
}

private struct PurchasePanelGroup: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let tint: Color
    let orders: [BrowserMailOrderSummary]
}

private struct BookingPanelGroup: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let tint: Color
    let bookings: [BrowserMailBookingSummary]
}

private struct InvoicePanelGroup: Identifiable {
    let id: String
    let title: String
    let systemImage: String
    let tint: Color
    let invoices: [BrowserMailInvoiceSummary]
}

// MARK: - DashCard

private struct DashCard<Content: View>: View {
    var dashed: Bool = false
    var fillsHeight: Bool = true
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: fillsHeight ? .infinity : nil, alignment: .topLeading)
        .background(dashed ? DashColor.sunken : DashColor.card,
                    in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(
                    dashed ? Color.white.opacity(0.1) : Color.white.opacity(0.06),
                    style: dashed ? StrokeStyle(lineWidth: 1, dash: [5, 4]) : StrokeStyle(lineWidth: 1)
                )
        }
    }
}

// MARK: - Section Header

private struct DashSidebarButton: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let isLoading: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(isSelected ? DashColor.primary : DashColor.tertiary)
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(isSelected ? DashColor.primary : DashColor.tertiary)
                    .lineLimit(1)

                Spacer(minLength: 8)

                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .scaleEffect(0.62)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(
                isSelected ? Color.white.opacity(0.09) : Color.clear,
                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? Color.white.opacity(0.08) : Color.clear, lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct DashSectionHeader: View {
    let title: String
    let count: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DashColor.tertiary)
                .frame(width: 18)
            Text(title)
                .font(.system(size: 16, weight: .semibold))
            Spacer()
            Text(count)
                .font(.system(size: 12, weight: .semibold).monospaced())
                .foregroundStyle(DashColor.muted)
        }
    }
}

private struct DashPanelHeader: View {
    let title: String
    let count: Int
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18)

            Text(title)
                .font(.system(size: 16, weight: .semibold))

            Spacer()

            Text("\(count)")
                .font(.system(size: 12, weight: .semibold).monospaced())
                .foregroundStyle(DashColor.muted)
        }
    }
}

private struct DashSubsectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DashColor.secondary)

            Text("\(count)")
                .font(.system(size: 10.5, weight: .semibold).monospaced())
                .foregroundStyle(DashColor.muted)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.06), in: Capsule())
        }
    }
}

// MARK: - Paging Footer

private struct DashPagingFooter: View {
    let hasMore: Bool
    let isLoading: Bool
    let onLoadMore: () -> Void
    @State private var didTriggerForAppearance = false

    var body: some View {
        Group {
            if hasMore {
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView()
                            .controlSize(.small)
                            .scaleEffect(0.7)
                    } else {
                        Circle()
                            .fill(DashColor.muted.opacity(0.5))
                            .frame(width: 5, height: 5)
                    }
                    Text(isLoading ? "Loading more" : "More")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(DashColor.faint)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
                .onTapGesture(perform: loadMoreIfPossible)
                .onAppear(perform: triggerOnceForAppearance)
                .onDisappear {
                    didTriggerForAppearance = false
                }
            } else {
                Color.clear.frame(height: 1)
            }
        }
    }

    private func triggerOnceForAppearance() {
        guard hasMore, !isLoading, !didTriggerForAppearance else { return }
        didTriggerForAppearance = true
        loadMoreIfPossible()
    }

    private func loadMoreIfPossible() {
        guard hasMore, !isLoading else { return }
        onLoadMore()
    }
}

// MARK: - Shipment Card

private struct DashShipmentCard: View {
    let shipment: BrowserMailShipmentSummary
    let onSelect: () -> Void
    @State private var hovered = false

    private var progress: Double {
        switch shipment.status.lowercased() {
        case "delivered":                             return 1.0
        case "out_for_delivery", "out for delivery": return 0.8
        case "in_transit", "in transit":             return 0.5
        case "shipped":                              return 0.3
        default:                                     return 0.15
        }
    }

    private var statusColors: (bg: Color, fg: Color) {
        switch shipment.status.lowercased() {
        case "delivered":
            return (Color(red: 0.08, green: 0.32, blue: 0.17).opacity(0.6), Color(red: 0.29, green: 0.86, blue: 0.5))
        case "out_for_delivery", "out for delivery":
            return (DashColor.amber.opacity(0.15), DashColor.amber)
        default:
            return (Color.white.opacity(0.08), DashColor.tertiary)
        }
    }

    private var barColor: Color {
        switch shipment.status.lowercased() {
        case "delivered":                             return Color(red: 0.29, green: 0.86, blue: 0.5)
        case "out_for_delivery", "out for delivery": return DashColor.amber
        default:                                     return Color(red: 0.23, green: 0.51, blue: 0.96)
        }
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 9, style: .continuous).fill(DashColor.sunken)
                        if let urlStr = shipment.imageUrl, let url = URL(string: urlStr) {
                            AsyncImage(url: url) { phase in
                                if case .success(let img) = phase {
                                    img.resizable().scaledToFill()
                                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                                } else {
                                    Image(systemName: "shippingbox").font(.system(size: 13)).foregroundStyle(DashColor.muted)
                                }
                            }
                        } else {
                            Image(systemName: "shippingbox").font(.system(size: 13)).foregroundStyle(DashColor.muted)
                        }
                    }
                    .frame(width: 42, height: 42)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(shipment.merchant ?? shipment.carrier ?? "Shipment")
                            .font(.system(size: 10, weight: .medium).monospaced())
                            .foregroundStyle(DashColor.muted)
                            .lineLimit(1)
                        Text(titleText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(DashColor.secondary)
                            .lineLimit(2)
                    }
                }

                HStack {
                    Text(shipment.status.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(statusColors.fg)
                        .padding(.horizontal, 7).padding(.vertical, 2.5)
                        .background(statusColors.bg, in: Capsule())
                    Spacer()
                }
                .padding(.top, 8).padding(.bottom, 7)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.07)).frame(height: 4)
                        Capsule().fill(barColor).frame(width: geo.size.width * progress, height: 4)
                    }
                }
                .frame(height: 4)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(hovered ? DashColor.rowHov : DashColor.row,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }

    private var titleText: String {
        let s = shipment.itemSummary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return s.isEmpty ? (shipment.merchant ?? "Package") : s
    }
}

// MARK: - Subscription Row

private struct DashSubscriptionRow: View {
    let sub: BrowserMailSubscriptionSummary
    let onSelect: () -> Void
    @State private var hovered = false

    private var statusKey: String {
        sub.status
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    private var isPast: Bool {
        statusKey.contains("cancel") ||
            statusKey.contains("expired") ||
            statusKey.contains("ended") ||
            statusKey.contains("inactive") ||
            statusKey.contains("terminated")
    }

    private var daysLeft: Int? {
        guard let ms = sub.nextPaymentDueAt else { return nil }
        return Calendar.current.dateComponents([.day], from: .now, to: Date(timeIntervalSince1970: ms / 1000)).day
    }

    private var tagInfo: (label: String, bg: Color, fg: Color) {
        if isPast {
            return (statusLabel, Color.white.opacity(0.08), DashColor.tertiary)
        }

        if statusKey.contains("fail") || statusKey.contains("past_due") || statusKey.contains("declin") {
            return ("Payment issue", overdueColors.bg, overdueColors.fg)
        }

        if statusKey.contains("pause") {
            return ("Paused", Color.white.opacity(0.08), DashColor.tertiary)
        }

        if statusKey.contains("trial") {
            return ("Trial", Color.white.opacity(0.08), DashColor.tertiary)
        }

        switch daysLeft {
        case let d? where d >= 0 && d <= 3: return ("Due soon",   overdueColors.bg,  overdueColors.fg)
        case let d? where d >= 0 && d <= 7: return ("Due in \(d)d", DashColor.amber.opacity(0.15), DashColor.amber)
        default:                  return ("Active",     Color.white.opacity(0.08), DashColor.tertiary)
        }
    }

    private var overdueColors: (bg: Color, fg: Color) {
        (Color(red: 0.94, green: 0.27, blue: 0.27).opacity(0.18),
         Color(red: 0.97, green: 0.53, blue: 0.44))
    }

    private var priceText: String {
        guard let amount = sub.amount else { return "" }
        return "\(sub.currency ?? "") \(amount.formatted(.number.precision(.fractionLength(2))))".trimmingCharacters(in: .whitespaces)
    }

    private var statusLabel: String {
        sub.status.replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }

    private var showsBillingDate: Bool {
        guard !renewText.isEmpty else { return false }
        if isPast || statusKey.contains("fail") || statusKey.contains("past_due") || statusKey.contains("declin") {
            return true
        }
        return (daysLeft ?? 0) >= 0
    }

    private var renewText: String {
        guard let ms = sub.nextPaymentDueAt else { return "" }
        return Date(timeIntervalSince1970: ms / 1000).formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(sub.provider)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DashColor.secondary)
                        .lineLimit(1)
                    Text([sub.itemSummary, priceText].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.system(size: 11.5))
                        .foregroundStyle(DashColor.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 5) {
                    Text(tagInfo.label)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(tagInfo.fg)
                        .padding(.horizontal, 9).padding(.vertical, 3)
                        .background(tagInfo.bg, in: Capsule())
                    if showsBillingDate {
                        let suffix = daysLeft.flatMap { $0 >= 0 ? " · \($0)d" : nil } ?? ""
                        Text(renewText + suffix)
                            .font(.system(size: 11.5))
                            .foregroundStyle(DashColor.tertiary)
                    }
                }
            }
            .padding(.horizontal, 15).padding(.vertical, 15)
            .frame(maxWidth: .infinity)
            .background(hovered ? DashColor.rowHov : DashColor.row,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// MARK: - Purchase Row

private struct DashPurchaseRow: View {
    let order: BrowserMailOrderSummary
    let onSelect: () -> Void
    @State private var hovered = false

    private static let avatarPalette: [(bg: UInt32, fg: UInt32)] = [
        (0x1e3a5f, 0x60a5fa), (0x1a3a2a, 0x4ade80), (0x3b1f1f, 0xf87171),
        (0x2d1f3b, 0xc084fc), (0x3b2c1a, 0xfb923c), (0x1a2d3b, 0x38bdf8)
    ]

    private var avatar: (bg: Color, fg: Color) {
        let pair = Self.avatarPalette[abs(order.merchant.hashValue) % Self.avatarPalette.count]
        return (Color(rgbHex: pair.bg), Color(rgbHex: pair.fg))
    }

    private var statusColors: (bg: Color, fg: Color) {
        switch order.status.lowercased() {
        case "delivered":
            return (Color(red: 0.08, green: 0.32, blue: 0.17).opacity(0.6), Color(red: 0.29, green: 0.86, blue: 0.5))
        case "shipped":
            return (Color(red: 0.12, green: 0.23, blue: 0.37).opacity(0.6), Color(rgbHex: 0x60a5fa))
        case "cancelled", "canceled":
            return (Color(red: 0.23, green: 0.12, blue: 0.12).opacity(0.6), Color(rgbHex: 0xf87171))
        default:
            return (Color.white.opacity(0.06), DashColor.faint)
        }
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous).fill(avatar.bg)
                    Text(String(order.merchant.prefix(1)).uppercased())
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(avatar.fg)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    let title = order.itemSummary.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty } ?? order.merchant
                    Text(title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DashColor.secondary)
                        .lineLimit(1)
                    let detail = [order.merchant, order.orderNumber.map { "Order \($0)" }].compactMap { $0 }.joined(separator: " · ")
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(DashColor.faint)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Text(order.status.replacingOccurrences(of: "_", with: " ").capitalized)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(statusColors.fg)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(statusColors.bg, in: Capsule())
            }
            .padding(.horizontal, 12).padding(.vertical, 11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(hovered ? DashColor.row : Color.clear,
                        in: RoundedRectangle(cornerRadius: 11, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// MARK: - Security Row

private struct DashSecurityRow: View {
    let alert: BrowserMailSecurityNotification
    let onSelect: () -> Void
    @State private var hovered = false

    private var displayDate: Date? {
        if let date = alert.message?.displayDate {
            return date
        }
        return Date(timeIntervalSince1970: (alert.occurredAt ?? alert.updatedAt) / 1000)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(alert.serviceName ?? alert.notificationType.split(separator: "_").map { $0.capitalized }.joined(separator: " "))
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(DashColor.secondary)
                        .lineLimit(1)
                    Text([alert.device, alert.location, alert.ipAddress].compactMap { $0 }.joined(separator: " · "))
                        .font(.system(size: 11.5))
                        .foregroundStyle(DashColor.muted)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if let date = displayDate {
                    Text(date.formatted(date: .abbreviated, time: .omitted))
                        .font(.system(size: 11.5))
                        .foregroundStyle(DashColor.tertiary)
                }
            }
            .padding(.horizontal, 15).padding(.vertical, 14)
            .frame(maxWidth: .infinity)
            .background(hovered ? DashColor.rowHov : DashColor.row,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// MARK: - Info Row

private struct DashInfoRow: View {
    enum TagStyle {
        case standard
        case accent
    }

    let systemImage: String
    let title: String
    let detail: String
    let tag: String
    let date: Date?
    var tagStyle: TagStyle = .standard
    let onSelect: () -> Void

    @State private var hovered = false

    private var normalizedTag: String {
        tag.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private var tagColors: (bg: Color, fg: Color) {
        switch tagStyle {
        case .accent:
            return (DashColor.amber.opacity(0.15), DashColor.amber)
        case .standard:
            switch tag.lowercased() {
            case "paid", "confirmed", "active", "open", "upcoming":
                return (Color(red: 0.08, green: 0.32, blue: 0.17).opacity(0.6), Color(red: 0.29, green: 0.86, blue: 0.5))
            case "overdue", "failed", "cancelled", "canceled":
                return (Color(red: 0.23, green: 0.12, blue: 0.12).opacity(0.6), Color(rgbHex: 0xf87171))
            default:
                return (Color.white.opacity(0.06), DashColor.faint)
            }
        }
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(DashColor.sunken)
                    Image(systemName: systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DashColor.tertiary)
                }
                .frame(width: 34, height: 34)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Untitled")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(DashColor.secondary)
                        .lineLimit(1)

                    Text(detail.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty ?? "Open original email for details")
                        .font(.system(size: 11))
                        .foregroundStyle(DashColor.faint)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .trailing, spacing: 5) {
                    Text(normalizedTag)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(tagColors.fg)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(tagColors.bg, in: Capsule())

                    if let date {
                        Text(date.formatted(date: .abbreviated, time: .omitted))
                            .font(.system(size: 10.5))
                            .foregroundStyle(DashColor.tertiary)
                            .monospacedDigit()
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
            .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
            .background(hovered ? DashColor.rowHov : DashColor.row,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

// MARK: - Tucked Stat

private struct DashTuckedStat: View {
    let count: Int
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text("\(count)")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(DashColor.dim)
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(DashColor.faint)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.03), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - Email Modal

private struct DashEmailModal: View {
    let message: BrowserMailDashboardMessage
    let onClose: () -> Void
    let onOpenMail: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.66)
                .ignoresSafeArea()
                .onTapGesture(perform: onClose)

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "envelope")
                            .font(.system(size: 12))
                            .foregroundStyle(DashColor.tertiary)
                        Text("ORIGINAL EMAIL")
                            .font(.system(size: 11.5, weight: .semibold))
                            .tracking(0.8)
                            .foregroundStyle(DashColor.dim)
                    }
                    Spacer()
                    Button(action: onClose) {
                        Text("✕")
                            .font(.system(size: 14))
                            .foregroundStyle(DashColor.dim)
                            .frame(width: 30, height: 30)
                            .background(Color.white.opacity(0.06),
                                        in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.bottom, 22)

                DashModalField("SUBJECT") {
                    Text(message.subject ?? "No subject")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(DashColor.primary)
                }
                .padding(.bottom, 18)

                DashModalField("FROM") {
                    Text(message.from ?? "Unknown")
                        .font(.system(size: 13.5))
                        .foregroundStyle(DashColor.secondary)
                        .textSelection(.enabled)
                }
                .padding(.bottom, 16)

                HStack(alignment: .top, spacing: 32) {
                    if let date = message.displayDate {
                        DashModalField("DATE") {
                            Text(DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .short))
                                .font(.system(size: 13))
                                .foregroundStyle(DashColor.dim)
                        }
                    }
                    DashModalField("MESSAGE ID") {
                        Text(message.providerMessageId)
                            .font(.system(size: 11.5, weight: .medium).monospaced())
                            .foregroundStyle(DashColor.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .textSelection(.enabled)
                    }
                }
                .padding(.bottom, 18)

                Divider().opacity(0.12).padding(.bottom, 18)

                Text(message.snippet ?? "No preview available.")
                    .font(.system(size: 14))
                    .foregroundStyle(DashColor.dim)
                    .lineSpacing(4)
                    .textSelection(.enabled)
                    .padding(.bottom, 22)

                Button(action: onOpenMail) {
                    HStack(spacing: 6) {
                        Text("Open original")
                        Text("↗").fontWeight(.bold)
                    }
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(DashColor.primary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 13)
                    .background(Color.white.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
            .padding(28)
            .frame(width: 500)
            .background(DashColor.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1))
            .shadow(color: .black.opacity(0.55), radius: 60, y: 20)
        }
    }
}

private struct DashModalField<Content: View>: View {
    let label: String
    @ViewBuilder var content: Content

    init(_ label: String, @ViewBuilder content: () -> Content) {
        self.label = label
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(DashColor.faint)
            content
        }
    }
}
