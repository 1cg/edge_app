<%@ extends ronin.RoninTemplate %>
<html>
  <head>
    <link type="text/css" rel="stylesheet" href="public/styles.css">
  </head>
  <body>
    <h1><span></span>ronin</h1>
    <p><a href="https://github.com/kprevas/ronin/wiki/Tutorial">tutorial</a></p>
    <p><a href="https://github.com/kprevas/ronin/wiki/Ronin">docs</a></p>
    <p><a href="https://github.com/kprevas/ronin/wiki/Ronin">docs</a></p>
    <p><a href="<%=urlFor(controller.Main#test())%>">A link to tests...</a></p>
  </body>
</html>
