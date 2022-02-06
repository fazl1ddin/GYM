let as = document.querySelectorAll(".navbar ul li .a");
let boxim = document.querySelectorAll(".mainClassAllContentBoxer img");
let hbesh = document.querySelectorAll(".mainClassAllContentBoxer h5");
let menu = document.querySelectorAll(".menu");
let imager = document.querySelectorAll(".imgImager");
let our = document.querySelectorAll(".our");
let prev = document.querySelector(".onleft");
let next = document.querySelector(".onright");
let num = {
    start: 0,
    end:1
}
let nike = document.querySelectorAll(".maiNikeGalleryBox");
let aleft = document.querySelector(".aleft");
let arigth = document.querySelector(".arigth");
let son = {
    sta: 0,
    mid: 1,
    kon: 2
}
as.forEach((item, index) => {
    item.addEventListener("click", function(event){
        for(let i = 0; i < as.length; i++){
            as[i].classList.remove("active");
        }
        item.classList.add("active");
    });
    item.addEventListener("mouseover", function(){
        let menid = document.querySelector(`#${item.textContent}`);
        menid.classList.add("hid");
            menid.addEventListener("mouseover", function(){
                menid.classList.add("hid");
            });
            menid.addEventListener("mouseout", function(){
                menid.classList.remove("hid");
            });
    });
    item.addEventListener("mouseout", function(){
        for(let i = 0; i < menu.length; i++){
            menu[i].classList.remove("hid");
        };
    });
});
boxim.forEach((item, index) => {
    item.addEventListener("mouseover", function(){
        if(item.getAttribute("data-bly") != null){
            let iget = item.getAttribute("data-bly");
            let menid = document.querySelector("#" + iget);
            menid.classList.add("bly");
                menid.addEventListener("mouseover", function(){
                    menid.classList.add("bly");
                });
                menid.addEventListener("mouseout", function(){
                    menid.classList.remove("bly");
                });
        };  
    });
    item.addEventListener("mouseout", function(){
        for(let i = 0; i < hbesh.length; i++){
            hbesh[i].classList.remove("bly");
        };
    });
});
imager.forEach((item, index) => {
    item.addEventListener("click", function(){
        if(item.getAttribute("data-img") === "like"){
            item.classList.add("fade");
            imager[index + 1].classList.remove("fade");
        } else if(item.getAttribute("data-img") === "unlike"){
            item.classList.add("fade");
            imager[index - 1].classList.remove("fade");
        };
    });
});
prev.addEventListener("click", function(){
    let numStart = num.start;
    let numEnd = num.end;
    num.start--;
    if(num.start < 0){
        num.start = our.length - 1;
    };
    num.end--;
    if(num.end < 0){
        num.end = our.length - 1
    };
    our[num.start].classList.add("start");
    our[num.end].classList.remove("start");
    our[numStart].classList.add("end");
    our[numEnd].classList.remove("end");
});
next.addEventListener("click", function(){
    let numStart = num.start;
    let numEnd = num.end;
    num.start++;
    if(num.start >= our.length){
        num.start = 0;
    };
    num.end++;
    if(num.end >= our.length){
        num.end = 0;
    };
    our[num.start].classList.add("start");
    our[numStart].classList.remove("start");
    our[num.end].classList.add("end");
    our[numEnd].classList.remove("end");
});
aleft.addEventListener("click", function(){
    let sonSta = son.sta;
    let sonMid = son.mid
    let sonKon = son.kon;
    son.sta--;
    if(son.sta < 0){
        son.sta = nike.length - 1;
    };
    son.mid--;
    if(son.mid < 0){
        son.mid = nike.length - 1
    };
    son.kon--;
    if(son.kon < 0){
        son.kon = nike.length - 1
    };
    nike[sonSta].classList.remove("sta");
    nike[son.sta].classList.add("sta");
    nike[sonMid].classList.remove("mid");
    nike[son.mid].classList.add("mid");
    nike[sonKon].classList.remove("kon");
    nike[son.kon].classList.add("kon");
});
arigth.addEventListener("click", function(){
    let sonSta = son.sta;
    let sonMid = son.mid
    let sonKon = son.kon;
    son.sta++;
    if(son.sta >= nike.length){
        son.sta = 0;
    };
    son.mid++;
    if(son.mid >= nike.length){
        son.mid = 0;
    };
    son.kon++;
    if(son.kon >= nike.length){
        son.kon = 0;
    };
    nike[son.sta].classList.add("sta");
    nike[sonSta].classList.remove("sta");
    nike[son.mid].classList.add("mid");
    nike[sonMid].classList.remove("mid");
    nike[son.kon].classList.add("kon");
    nike[sonKon].classList.remove("kon");
});