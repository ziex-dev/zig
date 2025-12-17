export const utf8_section linksection("test-utf8") = [_]u8{'a','b','c','d'};

export const non_utf8_section linksection("test-non-utf8") = [_]u8{0,1,2};

export const duplicate_name1 linksection("dupe-name") = [_]u8{'o','n','e'};
export const duplicate_name2 linksection("dupe-name") = [_]u8{'t','w','o'};
