#!/usr/bin/env bash
#
# git-sync.sh - 二次开发 Git 同步管理工具
# 用于管理 fork 项目与上游仓库的同步
#

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 配置
UPSTREAM_REMOTE="upstream"
ORIGIN_REMOTE="origin"
MAIN_BRANCH="main"
DEV_BRANCH="dev/custom"

print_header() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║    DemonBot Git 同步管理工具           ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
    echo ""
}

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否在 git 仓库中
check_git_repo() {
    if ! git rev-parse --is-inside-work-tree &>/dev/null; then
        print_error "当前目录不是 git 仓库"
        exit 1
    fi
}

# 检查工作区是否干净
check_clean_workspace() {
    if ! git diff --quiet || ! git diff --cached --quiet; then
        print_warn "工作区有未提交的修改："
        git status --short
        echo ""
        read -rp "是否继续？(y/N) " confirm
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            print_status "操作已取消"
            exit 0
        fi
    fi
}

# 显示当前状态
show_status() {
    print_header
    echo -e "${YELLOW}── 当前状态 ──${NC}"
    echo ""

    local current_branch
    current_branch=$(git branch --show-current)
    echo -e "  当前分支:  ${GREEN}${current_branch}${NC}"
    echo ""

    # 显示 remote 信息
    echo -e "${YELLOW}── Remote 配置 ──${NC}"
    echo ""
    git remote -v | while read -r line; do
        echo "  $line"
    done
    echo ""

    # 检查上游更新
    print_status "正在检查上游更新..."
    git fetch "$UPSTREAM_REMOTE" --quiet 2>/dev/null || {
        print_warn "无法连接上游仓库"
        return
    }
    git fetch "$ORIGIN_REMOTE" --quiet 2>/dev/null || true

    local local_main upstream_main
    local_main=$(git rev-parse "$MAIN_BRANCH" 2>/dev/null || echo "N/A")
    upstream_main=$(git rev-parse "$UPSTREAM_REMOTE/$MAIN_BRANCH" 2>/dev/null || echo "N/A")

    if [[ "$local_main" == "$upstream_main" ]]; then
        print_success "本地 main 与上游同步 (最新)"
    else
        local behind_count
        behind_count=$(git rev-list --count "$MAIN_BRANCH".."$UPSTREAM_REMOTE/$MAIN_BRANCH" 2>/dev/null || echo "?")
        print_warn "上游有 ${behind_count} 个新提交待同步"
        echo ""
        echo -e "  ${YELLOW}最近的上游提交:${NC}"
        git log --oneline "$MAIN_BRANCH".."$UPSTREAM_REMOTE/$MAIN_BRANCH" 2>/dev/null | head -10 | while read -r line; do
            echo "    $line"
        done
    fi
    echo ""
}

# 同步上游代码到本地 main
sync_upstream() {
    print_header
    echo -e "${YELLOW}── 同步上游仓库 ──${NC}"
    echo ""

    check_clean_workspace

    local current_branch
    current_branch=$(git branch --show-current)

    print_status "拉取上游最新代码..."
    git fetch "$UPSTREAM_REMOTE"

    print_status "切换到 $MAIN_BRANCH 分支..."
    git checkout "$MAIN_BRANCH"

    print_status "合并上游 $MAIN_BRANCH..."
    if git merge "$UPSTREAM_REMOTE/$MAIN_BRANCH"; then
        print_success "上游代码合并成功"
    else
        print_error "合并冲突！请手动解决后运行: git merge --continue"
        exit 1
    fi

    print_status "推送到你的 fork..."
    git push "$ORIGIN_REMOTE" "$MAIN_BRANCH"
    print_success "fork 的 main 已更新"

    # 询问是否也更新开发分支
    echo ""
    read -rp "是否将更新合并到 $DEV_BRANCH？(Y/n) " merge_dev
    if [[ "$merge_dev" != "n" && "$merge_dev" != "N" ]]; then
        merge_main_to_dev
    else
        git checkout "$current_branch"
    fi

    echo ""
    print_success "同步完成！"
}

# 合并 main 到开发分支
merge_main_to_dev() {
    print_status "切换到 $DEV_BRANCH..."
    git checkout "$DEV_BRANCH"

    echo ""
    echo -e "  选择合并方式："
    echo -e "    ${GREEN}1)${NC} merge  - 保留完整历史（推荐多人协作）"
    echo -e "    ${GREEN}2)${NC} rebase - 更干净的历史（推荐个人开发）"
    echo ""
    read -rp "请选择 (1/2, 默认 1): " merge_type

    case "${merge_type:-1}" in
        2)
            print_status "正在 rebase $MAIN_BRANCH..."
            if git rebase "$MAIN_BRANCH"; then
                print_success "rebase 成功"
                git push "$ORIGIN_REMOTE" "$DEV_BRANCH" --force-with-lease
            else
                print_error "rebase 冲突！请解决后运行: git rebase --continue"
                exit 1
            fi
            ;;
        *)
            print_status "正在 merge $MAIN_BRANCH..."
            if git merge "$MAIN_BRANCH"; then
                print_success "merge 成功"
                git push "$ORIGIN_REMOTE" "$DEV_BRANCH"
            else
                print_error "合并冲突！请解决后运行: git merge --continue"
                exit 1
            fi
            ;;
    esac
}

# 拉取自己 fork 的最新代码
pull_origin() {
    print_header
    echo -e "${YELLOW}── 拉取 Fork 仓库代码 ──${NC}"
    echo ""

    local current_branch
    current_branch=$(git branch --show-current)

    echo -e "  当前分支: ${GREEN}${current_branch}${NC}"
    echo ""
    echo -e "  选择要拉取的分支："
    echo -e "    ${GREEN}1)${NC} 当前分支 ($current_branch)"
    echo -e "    ${GREEN}2)${NC} $MAIN_BRANCH"
    echo -e "    ${GREEN}3)${NC} $DEV_BRANCH"
    echo -e "    ${GREEN}4)${NC} 输入其他分支名"
    echo ""
    read -rp "请选择 (1-4, 默认 1): " choice

    local target_branch
    case "${choice:-1}" in
        2) target_branch="$MAIN_BRANCH" ;;
        3) target_branch="$DEV_BRANCH" ;;
        4)
            read -rp "请输入分支名: " target_branch
            ;;
        *) target_branch="$current_branch" ;;
    esac

    if [[ "$target_branch" != "$current_branch" ]]; then
        check_clean_workspace
        print_status "切换到 $target_branch..."
        git checkout "$target_branch"
    fi

    print_status "拉取 $ORIGIN_REMOTE/$target_branch..."
    git pull "$ORIGIN_REMOTE" "$target_branch"
    print_success "拉取完成！"
}

# 创建新功能分支
create_feature() {
    print_header
    echo -e "${YELLOW}── 创建功能分支 ──${NC}"
    echo ""

    read -rp "请输入功能名称 (例如: add-wechat): " feature_name
    if [[ -z "$feature_name" ]]; then
        print_error "功能名称不能为空"
        exit 1
    fi

    local branch_name="dev/${feature_name}"

    check_clean_workspace

    print_status "基于 $DEV_BRANCH 创建分支 $branch_name..."
    git checkout "$DEV_BRANCH"
    git pull "$ORIGIN_REMOTE" "$DEV_BRANCH"
    git checkout -b "$branch_name"
    git push -u "$ORIGIN_REMOTE" "$branch_name"

    print_success "功能分支 $branch_name 创建完成！"
    echo ""
    echo -e "  完成开发后，合并回 $DEV_BRANCH："
    echo -e "    git checkout $DEV_BRANCH"
    echo -e "    git merge $branch_name"
}

# 主菜单
main_menu() {
    print_header

    echo -e "  请选择操作："
    echo ""
    echo -e "    ${GREEN}1)${NC} 查看状态      - 查看分支、remote、上游更新情况"
    echo -e "    ${GREEN}2)${NC} 同步上游      - 拉取上游最新代码合并到 main 和 dev"
    echo -e "    ${GREEN}3)${NC} 拉取 Fork     - 拉取自己仓库的最新代码"
    echo -e "    ${GREEN}4)${NC} 创建功能分支  - 基于 dev/custom 创建新功能分支"
    echo -e "    ${GREEN}5)${NC} 退出"
    echo ""
    read -rp "请选择 (1-5): " choice

    case "$choice" in
        1) show_status ;;
        2) sync_upstream ;;
        3) pull_origin ;;
        4) create_feature ;;
        5) echo ""; print_status "再见！"; exit 0 ;;
        *) print_error "无效选择"; main_menu ;;
    esac
}

# 支持直接传参调用
check_git_repo

case "${1:-}" in
    status)   show_status ;;
    sync)     sync_upstream ;;
    pull)     pull_origin ;;
    feature)  create_feature ;;
    help)
        echo "用法: $0 [命令]"
        echo ""
        echo "命令:"
        echo "  status   查看当前状态和上游更新"
        echo "  sync     同步上游仓库代码"
        echo "  pull     拉取自己 fork 的代码"
        echo "  feature  创建新功能分支"
        echo "  help     显示帮助"
        echo ""
        echo "不带参数则进入交互式菜单"
        ;;
    "")       main_menu ;;
    *)        print_error "未知命令: $1"; echo "运行 '$0 help' 查看帮助"; exit 1 ;;
esac
