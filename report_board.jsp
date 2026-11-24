<%@ page language="java" contentType="text/html; charset=UTF-8"
    pageEncoding="UTF-8" %>
<%@ page import="java.sql.*" %>
<%@ page import="java.util.*" %>
<%@ page import="javafile.Report" %>
<!-- api키나 오라클 유저 비밀번호 부분 따로 관리 (home_page.jsp와 동일) -->
<%@ include file="./config.jsp" %>

<%!
    // HTML 특수문자 변환 (작성자가 입력한 제목/내용이 태그로 실행되는 것을 방지)
    private String esc(String s) {
        if (s == null) return "";
        return s.replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("\"", "&quot;")
                .replace("'", "&#39;");
    }
%>

<%
    request.setCharacterEncoding("UTF-8");

    // ===================== 1. 로그인 상태 확인 =====================
    // session.getAttribute("키") : 세션에 저장해 둔 값을 꺼내는 메서드 (반환 타입이 Object라서 형변환 필요)
    //  - 로그인할 때 세션에 저장하는 정보 : id, name, role
    //  - 세션에 값이 없으면(로그인 안 함) null, 있으면 저장된 값이 반환됨
    String id = (String) session.getAttribute("id");

    // 아래 정보가 필요해지면 주석(//)을 지우고 사용하세요.
    // String name = (String) session.getAttribute("name"); // 로그인한 사용자 이름
    // String role = (String) session.getAttribute("role"); // 권한 (예: "ADMIN")

    // id가 null이면 로그인 전이므로 로그인 페이지로 보내고 이 페이지는 여기서 종료
    if (id == null) {
        out.println("<script>");
        out.println("alert('로그인이 필요한 서비스입니다.');");
        out.println("location.href='" + request.getContextPath() + "/login.jsp';");
        out.println("</script>");
        return;
    }

    // ===================== 2. 요청 파라미터 처리 =====================
    // report_board.jsp?report_id=3  -> 상세보기
    // report_board.jsp?page=2       -> 목록 (report_id가 없으면 목록)
    final int PAGE_SIZE = 10;   // 한 페이지에 보여줄 게시글 수

    int currentPage = 1;
    try { currentPage = Integer.parseInt(request.getParameter("page")); } catch (Exception e) { currentPage = 1; }
    if (currentPage < 1) currentPage = 1;

    int detailId = 0;
    try { detailId = Integer.parseInt(request.getParameter("report_id")); } catch (Exception e) { detailId = 0; }

    // ===================== 3. DB 조회 =====================
    List<Report> boardList = new ArrayList<>();
    Report detail = null;
    String detailWasteType = "";   // Report 클래스에 waste_type 필드가 없어서 따로 저장
    int totalCount = 0;
    int totalPages = 1;
    boolean dbError = false;

    try {
        Class.forName("oracle.jdbc.driver.OracleDriver");

        try (Connection conn = DriverManager.getConnection(url, user, pw)) {

            if (detailId > 0) {
                // ----- [상세보기] 게시글 1개 조회 -----
                String detailSql = "SELECT report_id, title, user_name, waste_type, latitude, longitude, content, status, "
                                 + "TO_CHAR(reg_date, 'YYYY-MM-DD HH24:MI') AS reg_date, admin_no "
                                 + "FROM report WHERE report_id = ?";

                try (PreparedStatement pstmt = conn.prepareStatement(detailSql)) {
                    pstmt.setInt(1, detailId);
                    try (ResultSet rs = pstmt.executeQuery()) {
                        if (rs.next()) {
                            detail = new Report(
                                rs.getInt("report_id"),
                                rs.getString("title"),
                                rs.getString("user_name"),
                                rs.getString("content"),
                                rs.getString("latitude"),
                                rs.getString("longitude"),
                                rs.getString("status"),
                                rs.getString("reg_date"),
                                rs.getInt("admin_no")
                            );
                            detailWasteType = rs.getString("waste_type");
                        }
                    }
                }

            } else {
                // ----- [목록] 전체 개수 -> 총 페이지 수 계산 -----
                try (PreparedStatement pstmt = conn.prepareStatement("SELECT COUNT(*) FROM report");
                     ResultSet rs = pstmt.executeQuery()) {
                    if (rs.next()) totalCount = rs.getInt(1);
                }
                totalPages = Math.max(1, (int) Math.ceil((double) totalCount / PAGE_SIZE));
                if (currentPage > totalPages) currentPage = totalPages;

                // ----- [목록] 현재 페이지 게시글 조회 (최신글이 위로) -----
                // OFFSET ? ROWS FETCH NEXT ? ROWS ONLY : Oracle 12c 이상 페이징 문법
                String listSql = "SELECT report_id, title, user_name, status, "
                               + "TO_CHAR(reg_date, 'YYYY-MM-DD') AS reg_date "
                               + "FROM report ORDER BY report_id DESC "
                               + "OFFSET ? ROWS FETCH NEXT ? ROWS ONLY";

                try (PreparedStatement pstmt = conn.prepareStatement(listSql)) {
                    pstmt.setInt(1, (currentPage - 1) * PAGE_SIZE);
                    pstmt.setInt(2, PAGE_SIZE);
                    try (ResultSet rs = pstmt.executeQuery()) {
                        while (rs.next()) {
                            // 목록에서 쓰지 않는 값은 null 혹은 0 (home_page.jsp와 같은 방식)
                            boardList.add(new Report(
                                rs.getInt("report_id"),
                                rs.getString("title"),
                                rs.getString("user_name"),
                                null,
                                null,
                                null,
                                rs.getString("status"),
                                rs.getString("reg_date"),
                                0
                            ));
                        }
                    }
                }
            }
        }

    } catch (Exception e) {
        e.printStackTrace();
        dbError = true;
    }

    // 상세보기 지도에 표시할 좌표 (DB에는 VARCHAR2로 저장되어 있어서 숫자로 변환)
    boolean hasCoord = false;
    double mapLat = 0;
    double mapLng = 0;
    if (detail != null) {
        try {
            mapLat = Double.parseDouble(detail.getLatitude());
            mapLng = Double.parseDouble(detail.getLongitude());
            hasCoord = true;
        } catch (Exception e) {
            hasCoord = false;
        }
    }
%>
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>신고 게시판</title>
<% if (hasCoord) { %>
<!-- 카카오지도 API (상세보기에서 신고 위치를 보여줄 때만 불러옴) -->
<script type="text/javascript" src="//dapi.kakao.com/v2/maps/sdk.js?appkey=<%= KAKAO_API_KEY %>"></script>
<% } %>
<!-- 스타일 분리 list.css -->
<link rel="stylesheet" href="${pageContext.request.contextPath}/stylefile/list.css">
</head>
<body>
<%@ include file="/header.jsp" %>

<div class="board-wrap">

<% if (detailId > 0) { %>
    <%-- ======================= 상세보기 ======================= --%>
    <% if (dbError) { %>
        <div class="board-empty">데이터를 불러오지 못했습니다. DB 연결(config.jsp)을 확인해 주세요.</div>
    <% } else if (detail == null) { %>
        <div class="board-empty">존재하지 않는 신고입니다.</div>
    <% } else { %>
        <div class="detail-box">
            <div class="detail-title"><%= esc(detail.getTitle()) %></div>

            <div class="detail-meta">
                <div class="label">작성자</div>
                <div><%= esc(detail.getUser_Name()) %></div>
                <div class="label">쓰레기 유형</div>
                <div><%= esc(detailWasteType) %></div>

                <div class="label">처리 상태</div>
                <div>
                    <% if ("해결완료".equals(detail.getStatus())) { %>
                        <span class="status-done">해결완료</span>
                    <% } else { %>
                        <span class="status-wait">접수</span>
                    <% } %>
                </div>
                <div class="label">작성일</div>
                <div><%= esc(detail.getReg_date()) %></div>

                <div class="label">위치 좌표</div>
                <div class="span3">위도 <%= esc(detail.getLatitude()) %> / 경도 <%= esc(detail.getLongitude()) %></div>
            </div>

            <%-- 줄바꿈(\n)을 <br>로 바꿔서 출력 --%>
            <div class="detail-content"><%= esc(detail.getContent()).replace("\r\n", "<br>").replace("\n", "<br>") %></div>
        </div>

        <% if (hasCoord) { %>
            <div class="detail-map-title">신고 위치</div>
            <div id="detail-map"></div>
            <script>
                // 신고된 위도/경도로 지도 중심 이동 + 마커 표시
                var pos = new kakao.maps.LatLng(<%= mapLat %>, <%= mapLng %>);
                var map = new kakao.maps.Map(document.getElementById('detail-map'), {
                    center: pos,
                    level: 4
                });
                new kakao.maps.Marker({ position: pos, map: map });
            </script>
        <% } %>

        <div class="detail-buttons">
            <a class="btn btn-gray" href="report_board.jsp?page=<%= currentPage %>">목록으로</a>
            <a class="btn" href="home_page.jsp">지도에서 전체 보기</a>
            <%--
                관리자 전용 버튼(처리 상태 변경 등)을 만들 때는 위쪽에서 role 주석을 해제하고 아래처럼 사용
                <% if ("ADMIN".equals(role)) { %>
                    <a class="btn" href="status_process.jsp?report_id=<%= detail.getReport_Id() %>">해결완료 처리</a>
                <% } %>
            --%>
        </div>
    <% } %>

<% } else { %>
    <%-- ======================= 목록 ======================= --%>
    <div class="board-top">
        <div>
            <h2>신고 게시판</h2>
            <p class="sub">로그인 ID : <%= esc(id) %> / 전체 <%= totalCount %>건</p>
        </div>
        <a class="btn" href="write.jsp">쓰레기 신고하기</a>
    </div>

    <table class="board-table">
        <thead>
            <tr>
                <th class="col-no">번호</th>
                <th>제목</th>
                <th class="col-writer">작성자</th>
                <th class="col-status">상태</th>
                <th class="col-date">작성일</th>
            </tr>
        </thead>
        <tbody>
        <% if (dbError) { %>
            <tr><td colspan="5" class="board-empty">데이터를 불러오지 못했습니다. DB 연결(config.jsp)을 확인해 주세요.</td></tr>
        <% } else if (boardList.isEmpty()) { %>
            <tr><td colspan="5" class="board-empty">접수된 신고 내역이 없습니다.</td></tr>
        <% } else {
               // 화면에 보이는 번호 (최신글이 가장 큰 번호)
               int rowNo = totalCount - (currentPage - 1) * PAGE_SIZE;
               for (Report r : boardList) { %>
            <tr>
                <td><%= rowNo-- %></td>
                <td class="col-title">
                    <a href="report_board.jsp?report_id=<%= r.getReport_Id() %>&page=<%= currentPage %>"><%= esc(r.getTitle()) %></a>
                </td>
                <td><%= esc(r.getUser_Name()) %></td>
                <td>
                    <% if ("해결완료".equals(r.getStatus())) { %>
                        <span class="status-done">해결완료</span>
                    <% } else { %>
                        <span class="status-wait">접수</span>
                    <% } %>
                </td>
                <td><%= esc(r.getReg_date()) %></td>
            </tr>
        <%     }
           } %>
        </tbody>
    </table>

    <%
        // 페이지 번호 계산 (5개씩 묶어서 표시)
        int blockSize = 5;
        int startPage = ((currentPage - 1) / blockSize) * blockSize + 1;
        int endPage = Math.min(startPage + blockSize - 1, totalPages);
    %>
    <div class="pagination">
        <% if (startPage > 1) { %>
            <a href="report_board.jsp?page=<%= startPage - 1 %>">&laquo;</a>
        <% } %>
        <% for (int p = startPage; p <= endPage; p++) {
               if (p == currentPage) { %>
            <span class="current"><%= p %></span>
        <%     } else { %>
            <a href="report_board.jsp?page=<%= p %>"><%= p %></a>
        <%     }
           } %>
        <% if (endPage < totalPages) { %>
            <a href="report_board.jsp?page=<%= endPage + 1 %>">&raquo;</a>
        <% } %>
    </div>
<% } %>

</div>
</body>
</html>
