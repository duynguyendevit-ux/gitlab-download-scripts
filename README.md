# GitLab Bulk Download Scripts

🚀 Công cụ download hàng loạt repositories từ GitLab với quản lý token tự động.

## ✨ Tính năng

- 📦 Download tất cả repos từ GitLab (theo group hoặc toàn bộ)
- 🔑 Lưu và quản lý access tokens tự động
- 🎯 2 chế độ: Source Only (nhanh) hoặc Full Clone (với git history)
- 📂 Tự động tạo thư mục `gitlab-repos/` trong thư mục hiện tại
- 🔒 Dùng SSH để clone (nhanh và bảo mật)
- 🗂️ Extract thư mục `src/` và loại bỏ config files

## 📋 Yêu cầu

- `bash` 4.0+
- `gum` (CLI tool) - [Cài đặt](https://github.com/charmbracelet/gum)
- `jq` - JSON processor
- `curl`
- `git`
- `rsync` (cho extract-src.sh)
- SSH key đã setup với GitLab

### Cài đặt dependencies

**Ubuntu/Debian:**
```bash
sudo apt install jq curl git rsync
sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list
sudo apt update && sudo apt install gum
```

**macOS:**
```bash
brew install gum jq curl git rsync
```

## 🚀 Cài đặt

```bash
git clone https://github.com/duynguyendevit-ux/gitlab-download-scripts.git
cd gitlab-download-scripts
chmod +x *.sh
```

## 📖 Hướng dẫn sử dụng

### 1. Setup SSH Key với GitLab

```bash
# Tạo SSH key (nếu chưa có)
ssh-keygen -t ed25519 -C "your_email@example.com"

# Copy public key
cat ~/.ssh/id_ed25519.pub

# Thêm vào GitLab: Settings → SSH Keys
```

Test kết nối:
```bash
ssh -T git@your-gitlab-host  # Thay bằng GitLab host của bạn
```

### 2. Tạo GitLab Personal Access Token

1. Đăng nhập GitLab
2. Settings → Access Tokens
3. Tạo token với scope: `read_api`, `read_repository`
4. Copy token (chỉ hiện 1 lần)

### 3. Download Repositories

```bash
./gitlab-bulk-download.sh
```

**Workflow:**
1. Nhập GitLab URL lần đầu (tự động lưu cho lần sau)
2. Nhập Personal Access Token (tự động lưu cho lần sau)
3. Chọn group/namespace hoặc "Tất cả projects"
4. Chọn mode:
   - **Source Only** (khuyến nghị): Chỉ code, nhanh hơn
   - **Full Clone**: Có git history
5. Script tự động download vào `./gitlab-repos/`

**Lần chạy tiếp theo:**
- URL và token đã lưu → Enter để dùng lại
- Không cần nhập lại

### 4. Extract Source Code

Sau khi download, extract thư mục `src/` và loại bỏ config files:

```bash
./extract-src.sh
```

**Workflow:**
1. Chọn thư mục chứa repos (file picker chỉ hiển thị folders có nội dung)
2. Chọn tạo folder mới hoặc chọn folder đích
3. Script tự động:
   - Tìm thư mục `src/` trong mỗi repo
   - Copy code
   - Loại bỏ: `.yml`, `.yaml`, `.properties`, `.env`, `.git`, `node_modules`, `target`, `build`, `dist`, `resources`

### 5. Quản lý Tokens

```bash
./gitlab-token-manager.sh
```

**Chức năng:**
- Xem danh sách tokens đã lưu
- Xóa token theo URL
- Xóa tất cả tokens

Tokens được lưu tại: `~/.gitlab-tokens.json` (permission 600)

## 📁 Cấu trúc thư mục

```
your-project/
├── gitlab-download-scripts/
│   ├── gitlab-bulk-download.sh
│   ├── extract-src.sh
│   └── gitlab-token-manager.sh
├── gitlab-repos/              # Repos đã download
│   ├── group1/
│   │   ├── project-a/
│   │   └── project-b/
│   └── group2/
│       └── project-c/
└── extracted-src/             # Source code đã extract
    ├── project-a/
    ├── project-b/
    └── project-c/
```

## 🔧 Troubleshooting

### Script dừng sau "🚀 Bắt đầu download..."

- Kiểm tra SSH key: `ssh -T git@your-gitlab-url`
- Kiểm tra token có quyền `read_repository`
- Thử mode "Source Only" thay vì "Full Clone"

### Permission denied (publickey)

```bash
# Thêm SSH key vào ssh-agent
eval "$(ssh-agent -s)"
ssh-add ~/.ssh/id_ed25519
```

### Token không lưu được

```bash
# Kiểm tra permission
ls -la ~/.gitlab-tokens.json
# Nếu không có, tạo thủ công:
touch ~/.gitlab-tokens.json
chmod 600 ~/.gitlab-tokens.json
```

## 🎯 Use Cases

**1. Backup toàn bộ GitLab:**
```bash
./gitlab-bulk-download.sh
# Chọn "Tất cả projects" → "Source Only"
```

**2. Clone 1 group cụ thể:**
```bash
./gitlab-bulk-download.sh
# Chọn group → "Full Clone" (nếu cần git history)
```

**3. Lấy code để phân tích:**
```bash
./gitlab-bulk-download.sh  # Download
./extract-src.sh           # Extract src/ only
```

## 📝 Notes

- **Source Only mode**: Nhanh hơn ~3-5x so với Full Clone
- **SSH vs HTTP**: SSH nhanh hơn và không cần token trong URL
- **Token security**: Tokens được lưu local với permission 600
- **Incremental download**: Repos đã tồn tại sẽ bị bỏ qua

## 🤝 Contributing

Pull requests welcome! Mở issue nếu gặp bug.

## 📄 License

MIT License - Free to use and modify

## 👤 Author

Duy Nguyen ([@dyan071](https://t.me/dyan071))

---

⭐ Star repo nếu thấy hữu ích!
