import SwiftUI
import WebKit

// MARK: - Browser State Models

/// A Tab model that holds its own WKWebView instance and navigation state.
/// This is the key to making tabs independent and persistent.
struct Tab: Identifiable, Hashable {
    let id = UUID()
    var url: URL
    var title: String = "New Tab"
    var webView: WKWebView? // Each tab now owns its web view
}

/// A HistoryEntry model to store browser history, which is now
/// a requested feature that will be displayed using HTML.
struct HistoryEntry: Identifiable, Encodable {
    let id = UUID()
    let url: URL
    let title: String
    let date: Date
}

/// Manages the overall state of the browser, including tabs, history, and downloads.
class NavigationState: ObservableObject {
    @Published var tabs: [Tab] = []
    @Published var currentTabIndex = 0
    @Published var history: [HistoryEntry] = []
    @Published var pageSource: String = ""

    /// Initializer to ensure there is always at least one tab.
    init() {
        addTab(url: URL(string: "https://www.google.com")!)
    }
    
    var currentTab: Tab? {
        tabs[safe: currentTabIndex]
    }

    func addTab(url: URL) {
        tabs.append(Tab(url: url))
        currentTabIndex = tabs.count - 1
    }

    func closeTab(at index: Int) {
        guard tabs.indices.contains(index) else { return }
        tabs[index].webView = nil
        tabs.remove(at: index)

        if tabs.isEmpty {
            addTab(url: URL(string: "https://www.google.com")!)
        } else {
            if currentTabIndex >= index {
                currentTabIndex = max(0, currentTabIndex - 1)
            }
        }
    }

    func updateTabURL(at index: Int, to url: URL) {
        guard tabs.indices.contains(index) else { return }
        tabs[index].url = url
    }

    func updateTabTitle(at index: Int, to title: String) {
        guard tabs.indices.contains(index) else { return }
        tabs[index].title = title
    }

    func addHistoryEntry(url: URL, title: String) {
        history.insert(HistoryEntry(url: url, title: title, date: Date()), at: 0)
    }

    func clearHistory() {
        history.removeAll()
    }
}

// MARK: - App Settings

class AppSettings: ObservableObject {
    @Published var allowJavaScript = true
    @Published var blockCanvas = false
    @Published var blockWebGL = false
    @Published var searchEngine: SearchEngine = .google
}

enum SearchEngine: String, CaseIterable, Identifiable {
    case google, bing, duckduckgo, brave, yahoo, flashseek
    var id: String { rawValue }

    var urlTemplate: String {
        switch self {
        case .google: return "https://www.google.com/search?q={query}"
        case .bing: return "https://www.bing.com/search?q={query}"
        case .duckduckgo: return "https://duckduckgo.com/?q={query}"
        case .brave: return "https://search.brave.com/search?q={query}"
        case .yahoo: return "https://search.yahoo.com/search?p={query}"
        case .flashseek: return "https://flashseek.vercel.app/?q={query}"
        }
    }
}

// MARK: - Downloads View Models

struct DownloadEntry: Identifiable, Encodable {
    let id: UUID
    let fileName: String
    let url: URL
    var progress: Double = 0
    var isFinished = false
    var error: String?
    var localURL: URL?

    init(id: UUID = UUID(), fileName: String, url: URL) {
        self.id = id
        self.fileName = fileName
        self.url = url
    }
}

class BrowserData: ObservableObject {
    @Published var downloads: [DownloadEntry] = []

    func addDownload(_ entry: DownloadEntry) {
        DispatchQueue.main.async { self.downloads.append(entry) }
    }

    func updateDownloadProgress(id: UUID, progress: Double) {
        if let index = downloads.firstIndex(where: { $0.id == id }) {
            downloads[index].progress = max(0, min(1, progress))
        }
    }

    func finishDownload(id: UUID, success: Bool, localURL: URL? = nil, error: String? = nil) {
        if let index = downloads.firstIndex(where: { $0.id == id }) {
            downloads[index].isFinished = true
            downloads[index].localURL = localURL
            downloads[index].error = error
            downloads[index].progress = success ? 1.0 : 0.0
        }
    }
}

// MARK: - Main ContentView

struct ContentView: View {
    @StateObject private var settings = AppSettings()
    @StateObject private var nav = NavigationState()
    @StateObject private var browserData = BrowserData()

    @State private var addressBarText = "https://www.google.com"
    @State private var isLoading = false
    @State private var showSettings = false
    @State private var showHistory = false
    @State private var showDownloads = false
    @State private var showSource = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var pendingInsecureRequest: URLRequest?

    var body: some View {
        VStack(spacing: 0) {
            tabBarView
            addressBarView
            Divider()
            contentArea
        }
        .frame(minWidth: 1100, minHeight: 800)
        .background(Color.white)
        // Use a generic view to display our HTML content
        .sheet(isPresented: $showSettings) { htmlContentView(html: settingsHTML) }
        .sheet(isPresented: $showHistory) { htmlContentView(html: historyHTML) }
        .sheet(isPresented: $showDownloads) { htmlContentView(html: downloadsHTML) }
        .sheet(isPresented: $showSource) { htmlContentView(html: pageSourceHTML) }
        .alert("Browser Alert", isPresented: $showAlert) {
            if pendingInsecureRequest != nil {
                Button("Allow") {
                    if let request = pendingInsecureRequest, let webView = nav.currentTab?.webView {
                        webView.load(request)
                        nav.updateTabURL(at: nav.currentTabIndex, to: request.url!)
                        addressBarText = request.url!.absoluteString
                    }
                    pendingInsecureRequest = nil
                }
                Button("Deny", role: .cancel) {
                    pendingInsecureRequest = nil
                }
            } else {
                Button("OK", role: .cancel) {}
            }
        } message: {
            Text(alertMessage)
        }
        .onChange(of: nav.currentTabIndex) { _, newIndex in
            if let newURL = nav.tabs[safe: newIndex]?.url {
                addressBarText = newURL.absoluteString
            }
        }
    }

    private var tabBarView: some View {
        HStack(spacing: 4) {
            ForEach(nav.tabs.indices, id: \.self) { i in
                let tab = nav.tabs[i]
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        nav.currentTabIndex = i
                    }
                }) {
                    HStack(spacing: 6) {
                        Text(tab.title)
                            .lineLimit(1)
                            .font(.subheadline)
                            .foregroundColor(i == nav.currentTabIndex ? .white : .gray)
                        Button(action: {
                            nav.closeTab(at: i)
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.white)
                                .opacity(0.8)
                        }
                        .buttonStyle(.plain)
                        .help("Close Tab")
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(i == nav.currentTabIndex ? Color.blue.opacity(0.8) : Color.gray.opacity(0.4))
                    .cornerRadius(8)
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                }
                .buttonStyle(.plain)
            }
            .transition(.scale)
            .animation(.spring(), value: nav.tabs.count)

            Spacer()

            Button {
                let newURL = URL(string: "https://www.google.com")!
                nav.addTab(url: newURL)
                addressBarText = newURL.absoluteString
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundColor(.blue.opacity(0.8))
            }
            .help("New Tab")
            .buttonStyle(.plain)
            .padding(.horizontal)
        }
        .padding(.vertical, 4)
        .background(Color.white.shadow(radius: 2))
    }

    private var addressBarView: some View {
        HStack(spacing: 10) {
            Group {
                Button(action: goBack) {
                    Image(systemName: "chevron.left")
                }
                .disabled(nav.currentTab?.webView?.canGoBack == false)
                .help("Back")
                .buttonStyle(ModernButtonStyle())

                Button(action: goForward) {
                    Image(systemName: "chevron.right")
                }
                .disabled(nav.currentTab?.webView?.canGoForward == false)
                .help("Forward")
                .buttonStyle(ModernButtonStyle())

                Button(action: loadPage) {
                    Image(systemName: "arrow.clockwise.circle")
                }
                .help("Reload")
                .buttonStyle(ModernButtonStyle())
            }
            .foregroundColor(.blue.opacity(0.8))
            .font(.title3)

            TextField("Enter URL or search", text: $addressBarText, onCommit: loadPage)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocorrectionDisabled()
                .frame(minWidth: 350)
                .padding(.vertical, 4)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(8)
                .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)

            if isLoading {
                ProgressView().frame(width: 20, height: 20)
            } else {
                Image(systemName: "checkmark.circle")
                    .foregroundColor(.green)
                    .opacity(0.6)
                    .frame(width: 20, height: 20)
            }

            Group {
                Button { showSettings = true } label: {
                    Image(systemName: "gearshape")
                }.help("Settings")

                Button { showDownloads = true } label: {
                    Image(systemName: "arrow.down.circle")
                }.help("Downloads")
                
                Button { showHistory = true } label: {
                    Image(systemName: "clock")
                }.help("History")
                
                Button { viewSource() } label: {
                    Image(systemName: "doc.plaintext")
                }.help("Page Source")
            }
            .foregroundColor(.blue.opacity(0.8))
            .font(.title3)
            .buttonStyle(ModernButtonStyle())
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color.white.shadow(radius: 2))
    }

    @ViewBuilder
    private var contentArea: some View {
        ZStack {
            ForEach(nav.tabs.indices, id: \.self) { i in
                BrowserWebView(
                    tab: nav.tabs[i],
                    isLoading: $isLoading,
                    addressBarText: $addressBarText,
                    nav: nav,
                    settings: settings,
                    browserData: browserData
                )
                .opacity(i == nav.currentTabIndex ? 1 : 0)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: nav.currentTabIndex)
    }

    
    /// A generic function to display HTML content in a sheet
    private func htmlContentView(html: String) -> some View {
        VStack {
            HStack {
                Spacer()
                Button("Close") {
                    if showSettings { showSettings = false }
                    if showDownloads { showDownloads = false }
                    if showHistory { showHistory = false }
                    if showSource { showSource = false }
                }
                .buttonStyle(ModernButtonStyle())
            }
            .padding()
            BrowserWebView(htmlContent: html, nav: nav, browserData: browserData, settings: settings)
        }
        .frame(minWidth: 800, minHeight: 600)
    }

    private func loadPage() {
        var input = addressBarText.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.isEmpty {
            input = "https://www.google.com"
        }

        let targetURL: URL? = {
            if input.hasPrefix("http://") || input.hasPrefix("https://") {
                return URL(string: input)
            } else if input.contains(".") && !input.contains(" ") {
                return URL(string: "https://\(input)")
            } else {
                let encoded = input.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                return URL(string: settings.searchEngine.urlTemplate.replacingOccurrences(of: "{query}", with: encoded))
            }
        }()

        guard let url = targetURL else {
            alertMessage = "Invalid input: \(addressBarText)"
            showAlert = true
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            if url.scheme == "http" {
                var httpsComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
                httpsComponents?.scheme = "https"
                if let httpsURL = httpsComponents?.url {
                    var request = URLRequest(url: httpsURL)
                    request.timeoutInterval = 3
                    URLSession.shared.dataTask(with: request) { _, response, _ in
                        DispatchQueue.main.async {
                            if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode < 400 {
                                self.nav.currentTab?.webView?.load(request)
                            } else {
                                pendingInsecureRequest = URLRequest(url: url)
                                alertMessage = "This site uses an insecure connection (HTTP). Do you want to allow it?"
                                showAlert = true
                            }
                        }
                    }.resume()
                    return
                }
            }
            
            nav.currentTab?.webView?.load(URLRequest(url: url))
            nav.updateTabURL(at: nav.currentTabIndex, to: url)
            addressBarText = url.absoluteString
        }
    }

    private func viewSource() {
        guard let webView = nav.currentTab?.webView else {
            alertMessage = "Web view not available."
            showAlert = true
            return
        }
        
        webView.evaluateJavaScript("document.documentElement.outerHTML.toString()") { result, _ in
            DispatchQueue.main.async {
                if let html = result as? String {
                    nav.pageSource = html
                    showSource = true
                } else {
                    alertMessage = "Could not get page source."
                    showAlert = true
                }
            }
        }
    }

    private func goBack() {
        nav.currentTab?.webView?.goBack()
    }

    private func goForward() {
        nav.currentTab?.webView?.goForward()
    }
    
    // MARK: - HTML Content for Modals
    
    private var settingsHTML: String {
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Settings</title>
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                    margin: 0;
                    padding: 20px;
                    background-color: #f0f0f5;
                    color: #333;
                    line-height: 1.6;
                }
                .container {
                    max-width: 800px;
                    margin: auto;
                    padding: 20px;
                    background: #fff;
                    border-radius: 12px;
                    box-shadow: 0 4px 15px rgba(0, 0, 0, 0.1);
                    transition: transform 0.3s ease-out;
                }
                .container:hover {
                    transform: translateY(-2px);
                }
                h1 {
                    color: #007aff;
                    text-align: center;
                    margin-bottom: 25px;
                }
                .section {
                    margin-bottom: 30px;
                    padding: 20px;
                    background-color: #f9f9fc;
                    border-radius: 8px;
                    border: 1px solid #e0e0e0;
                }
                h2 {
                    color: #555;
                    border-bottom: 2px solid #007aff;
                    padding-bottom: 8px;
                    margin-top: 0;
                }
                .setting-item {
                    display: flex;
                    justify-content: space-between;
                    align-items: center;
                    margin-bottom: 15px;
                }
                .setting-item label {
                    font-size: 16px;
                    font-weight: 500;
                }
                select, button {
                    padding: 10px 15px;
                    border-radius: 8px;
                    border: 1px solid #ccc;
                    font-size: 16px;
                    cursor: pointer;
                    transition: all 0.2s ease-in-out;
                }
                button {
                    background-color: #007aff;
                    color: white;
                    border: none;
                }
                button:hover {
                    background-color: #0056b3;
                    box-shadow: 0 4px 10px rgba(0, 122, 255, 0.3);
                }
                .toggle-switch {
                    position: relative;
                    display: inline-block;
                    width: 48px;
                    height: 28px;
                }
                .toggle-switch input {
                    opacity: 0;
                    width: 0;
                    height: 0;
                }
                .slider {
                    position: absolute;
                    cursor: pointer;
                    top: 0;
                    left: 0;
                    right: 0;
                    bottom: 0;
                    background-color: #ccc;
                    transition: .4s;
                    border-radius: 28px;
                }
                .slider:before {
                    position: absolute;
                    content: "";
                    height: 20px;
                    width: 20px;
                    left: 4px;
                    bottom: 4px;
                    background-color: white;
                    transition: .4s;
                    border-radius: 50%;
                }
                input:checked + .slider {
                    background-color: #007aff;
                }
                input:checked + .slider:before {
                    transform: translateX(20px);
                }
            </style>
        </head>
        <body>
            <div class="container">
                <h1>Browser Settings</h1>
                <div class="section">
                    <h2>Privacy</h2>
                    <div class="setting-item">
                        <label>Allow JavaScript</label>
                        <label class="toggle-switch">
                            <input type="checkbox" id="js-toggle" checked>
                            <span class="slider"></span>
                        </label>
                    </div>
                    <div class="setting-item">
                        <label>Block Canvas Access</label>
                        <label class="toggle-switch">
                            <input type="checkbox" id="canvas-toggle">
                            <span class="slider"></span>
                        </label>
                    </div>
                    <div class="setting-item">
                        <label>Block WebGL Access</label>
                        <label class="toggle-switch">
                            <input type="checkbox" id="webgl-toggle">
                            <span class="slider"></span>
                        </label>
                    </div>
                </div>
                <div class="section">
                    <h2>Search Engine</h2>
                    <div class="setting-item">
                        <label for="search-engine">Default Search Engine</label>
                        <select id="search-engine">
                            <option value="google">Google</option>
                            <option value="bing">Bing</option>
                            <option value="duckduckgo">DuckDuckGo</option>
                        </select>
                    </div>
                </div>
                <div style="text-align: center;">
                    <button onclick="saveSettings()">Save and Close</button>
                </div>
            </div>
            <script>
                function saveSettings() {
                    const settings = {
                        allowJavaScript: document.getElementById('js-toggle').checked,
                        blockCanvas: document.getElementById('canvas-toggle').checked,
                        blockWebGL: document.getElementById('webgl-toggle').checked,
                        searchEngine: document.getElementById('search-engine').value
                    };
                    window.webkit.messageHandlers.message.postMessage({ type: 'settings', payload: settings });
                }
            </script>
        </body>
        </html>
        """
    }

    private var downloadsHTML: String {
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Downloads</title>
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                    background-color: #f0f0f5;
                    margin: 0;
                    padding: 20px;
                    color: #333;
                }
                .container {
                    max-width: 800px;
                    margin: auto;
                    background: #fff;
                    padding: 20px;
                    border-radius: 12px;
                    box-shadow: 0 4px 15px rgba(0, 0, 0, 0.1);
                }
                h1 {
                    color: #007aff;
                    text-align: center;
                    margin-bottom: 25px;
                }
                ul {
                    list-style-type: none;
                    padding: 0;
                }
                li {
                    background-color: #f9f9fc;
                    border: 1px solid #e0e0e0;
                    border-radius: 8px;
                    padding: 15px;
                    margin-bottom: 10px;
                    transition: box-shadow 0.2s;
                }
                li:hover {
                    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.08);
                }
                .file-name {
                    font-weight: bold;
                    color: #555;
                }
                .progress-bar {
                    height: 8px;
                    background-color: #e9ecef;
                    border-radius: 4px;
                    margin-top: 8px;
                }
                .progress-fill {
                    height: 100%;
                    background-color: #007aff;
                    border-radius: 4px;
                    transition: width 0.3s ease-in-out;
                }
                .status {
                    font-size: 14px;
                    margin-top: 5px;
                    color: #888;
                }
            </style>
        </head>
        <body>
            <div class="container">
                <h1>Downloads</h1>
                <ul id="downloads-list">
                    <!-- Download items will be injected here by JavaScript -->
                </ul>
            </div>
            <script>
                window.onload = () => {
                    // Tell Swift to send the downloads data
                    window.webkit.messageHandlers.message.postMessage({ type: 'getDownloads' });
                };
                
                function updateDownloads(downloads) {
                    const list = document.getElementById('downloads-list');
                    if (downloads.length === 0) {
                        list.innerHTML = `<li style="text-align: center; color: #888;">No downloads yet.</li>`;
                        return;
                    }
                    list.innerHTML = downloads.map(d => {
                        const statusColor = d.isFinished ? '#28a745' : (d.error ? '#dc3545' : '#007aff');
                        const statusText = d.isFinished ? 'Completed' : (d.error ? 'Error: ' + d.error : 'Downloading...');
                        const progress = d.isFinished && !d.error ? 100 : (d.progress * 100).toFixed(0);
                        
                        return `
                            <li>
                                <div class="file-name">${d.fileName}</div>
                                <div class="progress-bar">
                                    <div class=\\\"progress-fill\\\" style=\\\"width: \\\\${progress}%;\\\"></div>
                                </div>
                                <div class=\\\"status\\\" style=\\\"color: \\\\${statusColor};\\\">\\\\${statusText}</div>
                            </li>
                        `;
                    }).join('');
                }
            </script>
        </body>
        </html>
        """
    }

    private var historyHTML: String {
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>History</title>
            <style>
                body {
                    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
                    background-color: #f0f0f5;
                    margin: 0;
                    padding: 20px;
                    color: #333;
                }
                .container {
                    max-width: 800px;
                    margin: auto;
                    background: #fff;
                    padding: 20px;
                    border-radius: 12px;
                    box-shadow: 0 4px 15px rgba(0, 0, 0, 0.1);
                }
                h1 {
                    color: #007aff;
                    text-align: center;
                    margin-bottom: 25px;
                }
                .history-list {
                    list-style-type: none;
                    padding: 0;
                }
                .history-item {
                    display: flex;
                    flex-direction: column;
                    background-color: #f9f9fc;
                    border: 1px solid #e0e0e0;
                    border-radius: 8px;
                    padding: 15px;
                    margin-bottom: 10px;
                    cursor: pointer;
                    transition: transform 0.2s, box-shadow 0.2s;
                }
                .history-item:hover {
                    transform: translateX(5px);
                    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.08);
                }
                .history-title {
                    font-weight: bold;
                    color: #007aff;
                }
                .history-url {
                    font-size: 14px;
                    color: #555;
                    word-break: break-all;
                }
                .history-date {
                    font-size: 12px;
                    color: #888;
                    margin-top: 5px;
                }
                .clear-button-container {
                    text-align: right;
                    margin-top: 20px;
                }
                .clear-button {
                    background-color: #ff3b30;
                    color: white;
                    border: none;
                    padding: 10px 20px;
                    border-radius: 8px;
                    font-size: 16px;
                    cursor: pointer;
                    transition: background-color 0.2s;
                }
                .clear-button:hover {
                    background-color: #cc2920;
                }
            </style>
        </head>
        <body>
            <div class="container">
                <h1>History</h1>
                <ul class="history-list" id="history-list">
                    <!-- History items will be injected here by JavaScript -->
                </ul>
                <div class="clear-button-container">
                    <button class="clear-button" onclick="clearHistory()">Clear All</button>
                </div>
            </div>
            <script>
                window.onload = () => {
                    // Tell Swift to send the history data
                    window.webkit.messageHandlers.message.postMessage({ type: 'getHistory' });
                };
                
                function updateHistory(history) {
                    const list = document.getElementById('history-list');
                    if (history.length === 0) {
                        list.innerHTML = `<li style="text-align: center; color: #888;">No history yet.</li>`;
                        return;
                    }
                    list.innerHTML = history.map(h => {
                        const date = new Date(h.date);
                        const formattedDate = date.toLocaleDateString() + ' ' + date.toLocaleTimeString();
                        return `
                            <li class="history-item" onclick="navigate('${h.url}')">
                                <span class="history-title">${h.title}</span>
                                <span class="history-url">${h.url}</span>
                                <span class="history-date">${formattedDate}</span>
                            </li>
                        `;
                    }).join('');
                }
                
                function navigate(url) {
                    // Tell Swift to navigate to this URL
                    window.webkit.messageHandlers.message.postMessage({ type: 'navigate', payload: url });
                }
                
                function clearHistory() {
                    // Tell Swift to clear all history
                    window.webkit.messageHandlers.message.postMessage({ type: 'clearHistory' });
                    updateHistory([]);
                }
            </script>
        </body>
        </html>
        """
    }
    
    private var pageSourceHTML: String {
        return """
        <!DOCTYPE html>
        <html lang="en">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>Page Source</title>
            <style>
                body {
                    font-family: Menlo, Monaco, 'Courier New', monospace;
                    background-color: #1e1e1e;
                    color: #d4d4d4;
                    margin: 0;
                    padding: 20px;
                }
                pre {
                    white-space: pre-wrap;
                    word-wrap: break-word;
                    font-size: 14px;
                    line-height: 1.5;
                }
                .container {
                    background: #252526;
                    padding: 20px;
                    border-radius: 12px;
                    box-shadow: 0 4px 15px rgba(0, 0, 0, 0.2);
                    height: 100%;
                    overflow-y: auto;
                }
            </style>
        </head>
        <body>
            <div class="container">
                <pre id="source-code">Loading page source...</pre>
            </div>
            <script>
                window.onload = () => {
                    // Tell Swift to send the page source
                    window.webkit.messageHandlers.message.postMessage({ type: 'getSource' });
                };
                
                function displaySource(source) {
                    document.getElementById('source-code').textContent = source;
                }
            </script>
        </body>
        </html>
        """
    }
}

// MARK: - Custom Button Style for better UI/UX

struct ModernButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(8)
            .background(Color.blue.opacity(configuration.isPressed ? 0.2 : 0.1))
            .cornerRadius(8)
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - BrowserWebView

struct BrowserWebView: NSViewRepresentable {
    var tab: Tab?
    var htmlContent: String?

    @Binding var isLoading: Bool
    @Binding var addressBarText: String
    @ObservedObject var nav: NavigationState
    @ObservedObject var settings: AppSettings
    @ObservedObject var browserData: BrowserData

    init(tab: Tab, isLoading: Binding<Bool>, addressBarText: Binding<String>, nav: NavigationState, settings: AppSettings, browserData: BrowserData) {
        self.tab = tab
        self.htmlContent = nil
        self._isLoading = isLoading
        self._addressBarText = addressBarText
        self.nav = nav
        self.settings = settings
        self.browserData = browserData
    }

    init(htmlContent: String, nav: NavigationState, browserData: BrowserData, settings: AppSettings) {
        self.tab = nil
        self.htmlContent = htmlContent
        self._isLoading = .constant(false)
        self._addressBarText = .constant("")
        self.nav = nav
        self.browserData = browserData
        self.settings = settings
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> WKWebView {
        if let existingWebView = tab?.webView {
            context.coordinator.webView = existingWebView
            return existingWebView
        }

        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences.allowsContentJavaScript = settings.allowJavaScript
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")

        let userContent = WKUserContentController()
        userContent.add(context.coordinator, name: "message")

        let userScript = WKUserScript(
            source: injectedJS(blockCanvas: settings.blockCanvas, blockWebGL: settings.blockWebGL),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        userContent.addUserScript(userScript)

        config.userContentController = userContent
        config.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        webView.customUserAgent = spoofedUserAgent()

        // Attach to coordinator and tab
        context.coordinator.webView = webView
        if let tabId = tab?.id, let index = nav.tabs.firstIndex(where: { $0.id == tabId }) {
            nav.tabs[index].webView = webView
        }

        if let html = htmlContent {
            webView.loadHTMLString(html, baseURL: nil)
        } else if let url = tab?.url, webView.url == nil {
            webView.load(URLRequest(url: url))
        }

        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKScriptMessageHandler {
        var parent: BrowserWebView
        var webView: WKWebView?

        init(_ parent: BrowserWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            DispatchQueue.main.async {
                if let tabId = self.parent.tab?.id, tabId == self.parent.nav.currentTab?.id {
                    self.parent.isLoading = true
                    self.parent.addressBarText = webView.url?.absoluteString ?? ""
                }
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            DispatchQueue.main.async {
                if let tabId = self.parent.tab?.id, tabId == self.parent.nav.currentTab?.id {
                    self.parent.isLoading = false
                    self.parent.addressBarText = webView.url?.absoluteString ?? ""
                    if let url = webView.url, let title = webView.title {
                        self.parent.nav.addHistoryEntry(url: url, title: title)
                    }
                }

                if let tabId = self.parent.tab?.id,
                   let index = self.parent.nav.tabs.firstIndex(where: { $0.id == tabId }) {
                    self.parent.nav.updateTabTitle(at: index, to: webView.title ?? "New Tab")
                    if let url = webView.url {
                        self.parent.nav.updateTabURL(at: index, to: url)
                    }
                }

                webView.alphaValue = 0
                NSAnimationContext.runAnimationGroup { context in
                    context.duration = 0.3
                    webView.animator().alphaValue = 1
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            DispatchQueue.main.async {
                if let tabId = self.parent.tab?.id, tabId == self.parent.nav.currentTab?.id {
                    self.parent.isLoading = false
                }
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            self.webView(webView, didFail: navigation, withError: error)
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "message" else { return }

            if let body = message.body as? [String: Any],
               let type = body["type"] as? String {
                switch type {
                case "console":
                    if let log = body["log"] as? String {
                        print("[JS Console]: \(log)")
                    }

                case "settings":
                    if let payload = body["payload"] as? [String: Any] {
                        if let allowJS = payload["allowJavaScript"] as? Bool {
                            parent.settings.allowJavaScript = allowJS
                        }
                        if let blockCanvas = payload["blockCanvas"] as? Bool {
                            parent.settings.blockCanvas = blockCanvas
                        }
                        if let blockWebGL = payload["blockWebGL"] as? Bool {
                            parent.settings.blockWebGL = blockWebGL
                        }
                        if let engineRaw = payload["searchEngine"] as? String,
                           let engine = SearchEngine(rawValue: engineRaw) {
                            parent.settings.searchEngine = engine
                        }
                    }

                case "getDownloads":
                    if let downloadsData = try? JSONEncoder().encode(parent.browserData.downloads),
                       let downloadsJSON = String(data: downloadsData, encoding: .utf8),
                       let webView = self.webView {
                        let script = "updateDownloads(\(downloadsJSON));"
                        webView.evaluateJavaScript(script)
                    }

                case "getHistory":
                    if let historyData = try? JSONEncoder().encode(parent.nav.history),
                       let historyJSON = String(data: historyData, encoding: .utf8),
                       let webView = self.webView {
                        let script = "updateHistory(\(historyJSON));"
                        webView.evaluateJavaScript(script)
                    }

                case "clearHistory":
                    parent.nav.clearHistory()

                case "getSource":
                    if !parent.nav.pageSource.isEmpty,
                       let webView = self.webView {
                        let source = parent.nav.pageSource
                        let escapedSource = source
                            .replacingOccurrences(of: "\\", with: "\\\\")
                            .replacingOccurrences(of: "'", with: "\\'")
                        let script = "displaySource(`\(escapedSource)`);"
                        webView.evaluateJavaScript(script)
                    }

                case "navigate":
                    if let urlString = body["payload"] as? String,
                       let url = URL(string: urlString),
                       let tabId = parent.tab?.id,
                       let index = parent.nav.tabs.firstIndex(where: { $0.id == tabId }) {
                        DispatchQueue.main.async {
                            self.parent.nav.tabs[index].url = url
                            self.parent.nav.currentTab?.webView?.load(URLRequest(url: url))
                        }
                    }

                default:
                    break
                }
            }
        }
    }

    // Optional: your JavaScript injection and spoofedUserAgent() functions go below.
    
    // MARK: - JavaScript Injections

    private func injectedJS(blockCanvas: Bool, blockWebGL: Bool) -> String {
        let blockCanvasString = blockCanvas ? "true" : "false"
        let blockWebGLString = blockWebGL ? "true" : "false"
        
        return """
        // ECMAScript 2025 Feature Detection
        window.addEventListener('load', () => {
            function checkFeature(name, test) {
                console.log(`[ECMAScript 2025] Does the browser support '${name}':`, test());
            }

            // RegExp v Flag()
            checkFeature("RegExp /v Flag()", () => {
                try {
                    const regex = new RegExp('', 'v');
                    return true;
                } catch {
                    return false;
                }
            });

            // RegExp.escape()
            checkFeature("RegExp.escape()", () => typeof RegExp.escape === 'function');
            
            // Float16Array
            checkFeature("Float16Array", () => typeof Float16Array !== 'undefined');
            
            // Math.f16round()
            checkFeature("Math.f16round()", () => typeof Math.f16round === 'function');
            
            // Promise.try()
            checkFeature("Promise.try()", () => typeof Promise.try === 'function');
            
            // Set methods
            const s1 = new Set([1, 2]);
            const s2 = new Set([2, 3]);
            checkFeature("Set union()", () => typeof s1.union === 'function');
            checkFeature("Set intersection()", () => typeof s1.intersection === 'function');
            checkFeature("Set difference()", () => typeof s1.difference === 'function');
            checkFeature("Set symmetricDifference()", () => typeof s1.symmetricDifference === 'function');
            checkFeature("Set isSubsetOf()", () => typeof s1.isSubsetOf === 'function');
            checkFeature("Set isSupersetOf()", () => typeof s1.isSupersetOf === 'function');
            checkFeature("Set isDisjointFrom()", () => typeof s1.isDisjointFrom === 'function');
            
            // Import Attributes
            checkFeature("Import Attributes", () => {
                try {
                    // This is a dynamic check, as static analysis is tricky
                    eval("import('./module.js', { with: { type: 'json' } })");
                    return true;
                } catch {
                    return false;
                }
            });
        });

        // Other Injections for anti-fingerprinting
        Object.defineProperty(navigator, 'webdriver', { get: () => false });
        Object.defineProperty(navigator, 'plugins', {
            get: () => [{ name: 'Chrome PDF Plugin', filename: 'internal-pdf-viewer', description: 'Portable Document Format' }]
        });
        Object.defineProperty(navigator, 'mimeTypes', {
            get: () => [{ type: 'application/pdf', description: 'Portable Document Format' }]
        });
        Object.defineProperty(navigator, 'languages', {
            get: () => ['en-US', 'en']
        });
        Object.defineProperty(navigator, 'deviceMemory', { get: () => 8 });
        Object.defineProperty(navigator, 'hardwareConcurrency', { get: () => 8 });
        Object.defineProperty(navigator, 'connection', {
            get: () => ({
                downlink: 10,
                effectiveType: '4g',
                rtt: 50,
                saveData: false
            })
        });
        Object.defineProperty(screen, 'width', { get: () => 1440 });
        Object.defineProperty(screen, 'height', { get: () => 900 });
        Object.defineProperty(screen, 'availWidth', { get: () => 1440 });
        Object.defineProperty(screen, 'availHeight', { get: () => 860 });
        Object.defineProperty(screen, 'colorDepth', { get: () => 24 });
        navigator.mediaDevices.enumerateDevices = async () => {
            return [
                { kind: 'audioinput', label: 'Built-in Microphone', deviceId: 'default' },
                { kind: 'videoinput', label: 'Built-in Camera', deviceId: 'default' }
            ];
        };
        Object.defineProperty(window, 'RTCPeerConnection', {
            get: () => function() {
                console.warn('[Spoof] WebRTC was blocked.');
                return null;
            }
        });
        Object.defineProperty(window, 'webkitRTCPeerConnection', {
            get: () => null
        });

        // Add a message handler to relay console logs to Swift
        const origConsoleLog = console.log;
        console.log = function(...args) {
            window.webkit.messageHandlers.message.postMessage({ type: 'console', log: args.join(' ') });
            origConsoleLog.apply(console, args);
        };

        const originalGetContext = HTMLCanvasElement.prototype.getContext;
        HTMLCanvasElement.prototype.getContext = function(type, ...args) {
            if ((\(blockCanvasString) && type.includes('2d')) || (\(blockWebGLString) && type.includes('webgl'))) {
                console.warn('[Canvas] Access Blocked for type: ' + type);
                return null;
            }
            return originalGetContext.apply(this, [type, ...args]);
        };

        if (!navigator.userAgentData) {
            navigator.userAgentData = {
                brands: [{ brand: 'Not-A.Brand', version: '99' }],
                platform: 'macOS',
                mobile: false,
                getHighEntropyValues: () => Promise.resolve({})
            };
        }

        (function() {
            const orig = console.log;
            console.log = function(...args) {
                window.webkit.messageHandlers.message.postMessage(args.join(' '));
                orig.apply(console, args);
            };
        })();
        """
    }

    // MARK: - User Agent Spoofing (Randomized Safari/Chrome Hybrid)

    func spoofedUserAgent() -> String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let major = os.majorVersion
        let minor = os.minorVersion

        let safariVersion = ["605.1.15", "605.1.13", "605.1.12"].randomElement()!
        let chromeVersion = ["117.0.5938.132", "116.0.5845.110", "115.0.5790.170"].randomElement()!
        let macOSString = "Macintosh; Intel Mac OS X \(major)_\(minor)"

        if major >= 14 {
            return "Mozilla/5.0 (\(macOSString)) AppleWebKit/\(safariVersion) (KHTML, like Gecko) Version/18.0 Safari/\(safariVersion)"
        } else if major == 13 {
            return "Mozilla/5.0 (\(macOSString)) AppleWebKit/\(safariVersion) (KHTML, like Gecko) Version/17.0 Safari/\(safariVersion)"
        } else {
            let userAgentChoices = [
                "Mozilla/5.0 (\(macOSString)) AppleWebKit/\(safariVersion) (KHTML, like Gecko) Version/16.0 Safari/\(safariVersion)",
                "Mozilla/5.0 (\(macOSString)) AppleWebKit/\(safariVersion) (KHTML, like Gecko) Version/15.0 Safari/\(safariVersion)",
                "Mozilla/5.0 (\(macOSString)) AppleWebKit/\(safariVersion) (KHTML, like Gecko) Version/14.0 Safari/\(safariVersion)",
                "Mozilla/5.0 (\(macOSString)) AppleWebKit/\(safariVersion) (KHTML, like Gecko) Version/13.0 Safari/\(safariVersion)",
                "Mozilla/5.0 (\(macOSString)) AppleWebKit/\(safariVersion) (KHTML, like Gecko) Version/12.0 Safari/\(safariVersion)",
                "Mozilla/5.0 (\(macOSString)) AppleWebKit/\(safariVersion) (KHTML, like Gecko) Version/11.0 Safari/\(safariVersion)",
                "Mozilla/5.0 (\(macOSString)) AppleWebKit/\(safariVersion) (KHTML, like Gecko) Version/10.0 Safari/\(safariVersion)",
                "Mozilla/5.0 (\(macOSString)) AppleWebKit/\(safariVersion) (KHTML, like Gecko) Version/9.0 Safari/\(safariVersion)",
                "Mozilla/5.0 (\(macOSString)) AppleWebKit/\(safariVersion) (KHTML, like Gecko) Version/8.0 Safari/\(safariVersion)",
                "Mozilla/5.0 (\(macOSString)) AppleWebKit/\(safariVersion) (KHTML, like Gecko) Version/7.0 Safari/\(safariVersion)",
                "Mozilla/5.0 (\(macOSString)) AppleWebKit/\(safariVersion) (KHTML, like Gecko) Version/6.0 Safari/\(safariVersion)",
                "Mozilla/5.0 (\(macOSString)) AppleWebKit/\(safariVersion) (KHTML, like Gecko) Version/5.0 Safari/\(safariVersion)",
                "Mozilla/5.0 (\(macOSString)) AppleWebKit/\(safariVersion) (KHTML, like Gecko) Version/4.0 Safari/\(safariVersion)"
            ].randomElement()!
            return userAgentChoices
        }
    }
}

// MARK: - Safe Array Access Extension

extension Collection {
    subscript(safe index: Index) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

