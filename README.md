# GitLab Bulk Download Scripts

🚀 Công cụ download hàng loạt repositories từ GitLab với quản lý token tự động.

## ✨ Tính năng

- 📦 Download tất cả repos từ GitLab (theo group hoặc toàn bộ)
- 🔑 Lưu và quản lý access tokens tự động
- 🎯 2 chế độ: Source Only (nhanh) hoặc Full Clone (với git history)
- 🎯 Download đúng tag/commit từ danh sách `project_path:git_ref`
- 📂 Tự động tạo thư mục `gitlab-repos/` trong thư mục hiện tại
- 🔒 Dùng SSH để clone (nhanh và bảo mật)
- 🗂️ Extract thư mục `src/` và loại bỏ config files

## 📋 Yêu cầu

- `bash` 3.2+
- `gum` (CLI tool) - [Cài đặt](https://github.com/charmbracelet/gum)
- `jq` - JSON processor
- `curl`
- `git`
- `ssh` (OpenSSH client)
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

### 3.1. Cấu hình và migration

Các script lưu cấu hình tại:

```text
~/.config/gitlabdowloadtool/
├── gitlab-tokens.json   # permission 600
└── gitlab-url.txt       # permission 600
```

Thư mục cấu hình có permission `700`. Khi khởi động, `gitlab-config.sh` tự
động tạo thư mục và sao chép các file legacy nếu file mới chưa tồn tại:

```text
~/.gitlab-tokens.json
~/.gitlab-url.txt
```

Các file legacy được giữ nguyên, không bị xóa. Token manager và các script
liên quan đều dùng cấu hình mới.

### 3.2. Download theo image path và revision

Ref-list vẫn có dạng `image_or_project_path:git_ref`. Dòng trống và dòng bắt
đầu bằng `#` được bỏ qua. Các input image path không cần trùng namespace GitLab;
script thử exact candidates theo thứ tự:

1. Path gốc
2. Bỏ tiền tố `ots/apps/`
3. Bỏ tiền tố `ots/`
4. Với path bắt đầu `ttdvkh/`, thử `c7-ttdvkh/`
5. Thử đổi segment `/notification/` thành `/notifications/`

Nếu không có exact project, script search theo basename cuối cùng và, khi tên
kết thúc bằng `-service`, thử thêm basename đã bỏ hậu tố đó. Mỗi search result
được kiểm tra revision qua GitLab API. Nếu có nhiều hoặc không có candidate
chứa revision, item bị fail và script in các candidate/action cần làm; script
không tự đoán.

Nếu pagination, API, transport, `429`, hoặc `5xx` làm verification không đầy
đủ, script cũng fail conservatively dù đã thấy một match. Hãy sửa quyền/kết
nối API rồi retry; dùng exact GitLab path hoặc explicit `tag@`/`commit@` để
giảm phạm vi tìm kiếm.

Revision có thể ghi theo các dạng sau:

- `7-40` ký tự hex không prefix: commit
- Ref không prefix khác: tag
- `tag@<name>`: tag, kể cả tag toàn hex
- `commit@<sha>`: commit bắt buộc `7-40` ký tự hex

Ví dụ:

```text
ots/apps/c7/infras/gateway:tag@prod-c7-v0.0.3
ots/apps/c7/qtud/category-service:e760bd05
ots/apps/c7/qtud/category-service:commit@e760bd05
```

Chạy với file hoặc stdin:

```bash
./gitlab-bulk-download.sh --ref-list refs.txt
cat refs.txt | ./gitlab-bulk-download.sh --ref-list -
```

Ref-list mode cần `git`, `ssh`, và SSH access tới GitLab. Script dùng
`.ssh_url_to_repo` do API trả về, không hardcode host/port. Với tag, Git được
shallow-clone đúng tag; với commit, script `git init`, thêm remote, fetch
`--depth 1` revision rồi checkout detached `FETCH_HEAD`. Sau đó `git archive`
export source-only, nên output không chứa `.git`.

Output dùng namespace GitLab đã resolve, không dùng path input:

```text
input:  ots/apps/c7/infras/gateway:tag@prod-c7-v0.0.3
output: gitlab-repos/c7/infras/gateway/
```

Mỗi item được stage trong thư mục ẩn bên trong `gitlab-repos/` rồi cài đặt
không ghi đè. Destination đã tồn tại được bỏ qua. Token API chỉ nằm trong
file curl tạm permission 600, không nằm trong command arguments. Summary gồm
Downloaded/Skipped/Failed và exit code khác 0 nếu có item fail.

Khi chạy `--ref-list`, sau khi xử lý hết input script tạo atomically manifest
`gitlab-repos/.gitlab-ref-projects.txt`. Manifest chứa mỗi resolved GitLab
`path_with_namespace` đúng một lần cho item đã download thành công trong chính
run hiện tại. Destination đã tồn tại hoặc xuất hiện trong race vẫn được skip
và giữ nguyên, nhưng bị loại khỏi manifest vì không có metadata đáng tin cậy để
chứng minh revision được yêu cầu; chỉ duplicate sau một install thành công
trong cùng run còn được biểu diễn bởi entry đã có. Item fail/không resolve cũng
không được ghi. Manifest vẫn được publish khi run có một phần lỗi, nên exit code
vẫn khác 0 nhưng manifest phản ánh subset đã download của ref-list hiện tại.
Ref-list rỗng tạo manifest rỗng.

Manifest cũng lưu identity revision theo dạng `tag:<tag-name>` hoặc
`commit:<canonical-full-sha>`. Cùng path với cùng identity (kể cả implicit và
explicit commit trỏ tới cùng canonical SHA) chỉ giữ một entry. Cùng path với
identity khác là conflicting duplicate: item bị fail, path bị loại khỏi
manifest, và cần tách revision/path trong ref-list.

### 4. Extract Source Code

Sau khi download, extract thư mục `src/` và loại bỏ config files:

```bash
./extract-src.sh
```

Chạy không tương tác bằng tham số dài hoặc ngắn:

```bash
./extract-src.sh --source ./gitlab-repos --destination ./extracted-src
./extract-src.sh -s ./gitlab-repos -d ./extracted-src
./extract-src.sh --source ./gitlab-repos --destination ./extracted-src \
  --manifest ./gitlab-repos/.gitlab-ref-projects.txt
./extract-src.sh --source ./gitlab-repos --destination ./extracted-src --all
```

Hai tham số `--source`/`--destination` phải đi theo cặp. Trong CLI, nếu không
ghi `--manifest` hoặc `--all` và source có manifest readable, script tự động
dùng manifest đó. `--manifest FILE` chỉ lọc các project an toàn được liệt kê;
dòng trống/comment bị bỏ qua, project không tồn tại chỉ cảnh báo rồi tiếp tục.
`--all` khôi phục scan toàn bộ source tree. Hai option này xung đột và lỗi với
exit code 2 nếu manifest không readable.

Chạy `./extract-src.sh` không có tham số vẫn mở workflow chọn thư mục tương
tác như trước. Nếu source có manifest, workflow hỏi `Chỉ projects từ ref-list
gần nhất` hoặc `Tất cả repositories` sau khi chọn source.

Filter chỉ tìm `src/` bên trong các project được chọn, vẫn giữ layout tương
đối và toàn bộ rsync exclusions hiện có. Mặc định manifest là subset đã
download thành công trong run hiện tại, không phải danh sách các destination
cũ bị skip. Vì vậy nên dùng source root mới/rỗng cho một run ref-list mới, hoặc
dùng `--all` khi muốn quét các repository đã có từ trước. Script không xóa file
trong destination đã dùng và rsync không có `--delete`; hãy chọn destination
mới/rỗng nếu cần snapshot chính xác, vì file stale trong destination cũ vẫn còn.
Nếu một project scan lỗi hoặc không đọc được, extractor báo lỗi, không coi run
là thành công và thoát với exit code 1.

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

Tokens được lưu tại: `~/.config/gitlabdowloadtool/gitlab-tokens.json`
(permission 600). URL đang dùng được lưu tại:
`~/.config/gitlabdowloadtool/gitlab-url.txt` (permission 600).

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
ls -ld ~/.config/gitlabdowloadtool
ls -l ~/.config/gitlabdowloadtool/gitlab-tokens.json
ls -l ~/.config/gitlabdowloadtool/gitlab-url.txt
```

Nếu bạn còn file `~/.gitlab-tokens.json` hoặc `~/.gitlab-url.txt`, chạy lại
script để helper tự động copy sang cấu hình mới. File cũ vẫn được giữ lại.

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

**4. Lấy code tại revision cụ thể:**
```bash
./gitlab-bulk-download.sh --ref-list refs.txt
```

## 📝 Notes

- **Source Only mode**: Nhanh hơn ~3-5x so với Full Clone
- **SSH vs HTTP**: SSH nhanh hơn và không cần token trong URL
- **Token security**: Tokens được lưu local với permission 600
- **Incremental download**: Repos đã tồn tại sẽ bị bỏ qua, không ghi đè hoặc xóa

## 🤝 Contributing

Pull requests welcome! Mở issue nếu gặp bug.

## 📄 License

MIT License - Free to use and modify

## 👤 Author

Duy Nguyen ([@dyan071](https://t.me/dyan071))

---

⭐ Star repo nếu thấy hữu ích!
